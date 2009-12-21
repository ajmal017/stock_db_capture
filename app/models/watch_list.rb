# == Schema Information
# Schema version: 20091220213712
#
# Table name: watch_list
#
#  id                :integer(4)      not null, primary key
#  ticker_id         :integer(4)
#  rsi_target_price  :float
#  price             :float
#  last_snaptime     :datetime
#  num_samples       :integer(4)
#  listed_on         :date
#  closed_on         :date
#  opening           :float
#  high              :float
#  low               :float
#  close             :float
#  volume            :integer(4)
#  last_seq          :integer(4)
#  current_rsi       :float
#  current_rvi       :float
#  target_rsi        :float
#  target_rvi        :float
#  open_crossed_at   :datetime
#  closed_crossed_at :datetime
#  min_delta         :float
#  nearest_indicator :string(255)
#  opened_on         :date
#  rvi_target_price  :float
#  last_populate     :datetime
#  last_rsi          :float
#  closing_rsi       :float
#  closing_condition :boolean(1)
#

# Copyright © Kevin P. Nolan 2009 All Rights Reserved.

#require 'faster_csv'

class WatchList < ActiveRecord::Base

  include TradingCalendar

  set_table_name 'watch_list'

  belongs_to :ticker
  has_one    :tda_position, :dependent => :nullify

  validates_presence_of :ticker_id
  validates_uniqueness_of :ticker_id, :scope => :listed_on

  ENTRY_HEADING = [ 'Symbol', 'Percentage', 'Price', 'Target RSI Price',  'Volume', 'Shares', 'RSI', 'Threshold', 'Listing', 'Open Crossing' ]
  ENTRY_COLUMNS = %w{ symbol target_percentage_f price_f rsi_target_price_f volume shares current_rsi_f target_rsi_f listed_on open_crossing }

  def symbol
    ticker.symbol
  end

  def status()
    @status ||= case
      when tda_position.nil? && opened_on.nil? : 'W'
      when tda_position.closed_at              : 'C'
      when tda_position.opened_at              : 'O'
    end
  end

  def to_shares
    price ? 10000.0/price : 0
  end

  def shares
    to_shares.floor
  end

  def days_held
    from_date = tda_position && tda_position.opened_at || opened_on
    to_date = tda_position && tda_position.closed_at || closed_on || Date.today
    from_date && to_date && trading_day_count(from_date, to_date, false)
  end

  def target_percentage_f
    target_percentage && format('%3.1f', target_percentage)
  end

  def price_f
    price && format('%3.2f', price)
  end

  def rsi_target_price_f
    rsi_target_price && format('%3.2f', rsi_target_price)
  end

  def rvi_target_price_f
    rvi_target_price && format('%3.2f', rvi_target_price)
  end

  def current_rsi_f
    current_rsi && format('%2.2f', current_rsi)
  end

  def current_rvi_f
    current_rvi && format('%2.2f', current_rvi)
  end

  def target_rsi_f
    target_rsi && format('%2.2f', target_rsi)
  end

  def open_crossing
    open_crossed_at && open_crossed_at.to_formatted_s(:pm)
  end

  def to_lots
    to_shares.zero? ? 0 : Math.log10(to_shares).floor ** 10
  end

  def target_percentage
    price && rsi_target_price && (price - rsi_target_price)/rsi_target_price * 100.0
  end

  def select_form
    "#{ticker.symbol} - #{open_crossed_at && open_crossed_at.to_date} - #{opened_on}"
  end

  def thresholds()
    rsi = target_rsi
    rvi = target_rvi
    [rsi, rvi].map(&:to_i).join(',')
  end

  def update_closure!(result_hash, last_bar, num_samples)
    attrs = { }
    attrs[:price] = last_bar[:close]
    indicators = result_hash.keys
    indicators.each do |indicator|
      attrs["current_#{indicator}".to_sym] = result_hash[indicator][:value]
      attrs["target_#{indicator}".to_sym] = result_hash[indicator][:threshold]
    end
    attrs[:nearest_indicator] = (min_ind = indicators.find { |ind| result_hash[ind].has_key? :min }).to_s
    attrs[:min_delta] = result_hash[min_ind][:delta]
    attrs[:last_snaptime] = last_bar[:time]
    attrs[:closed_crossed_at] = last_bar[:time] if indicators.any? { |ind| result_hash[ind][:crossed] }
    attrs[:num_samples] = num_samples
    update_attributes!(attrs)
  end

  class << self
    # TODO what happen when there's more than one watch list entry for a target id!
    def create_or_update_listing(ticker_id, rsi_target_price, current_rsi, target_rsi, listing_date, options={})
      logger = options[:logger]
      listings = find(:all, :conditions => { :ticker_id => ticker_id, :opened_on => nil })
      listings.each do |listing|
        listing.toggle!(:open_crossed_at) if listing.open_crossed_at
        listing.update_attributes!(:rsi_target_price => rsi_target_price, :target_rsi => target_rsi)
        logger.info("Updated Listing values on #{listing.symbol} #{listing.listed_on.to_s(:db)} to #{listing.rsi_target_price} for RSI #{listing.target_rsi}") if logger
      end
      if listings.empty?
        listing = create!(:ticker_id => ticker_id, :rsi_target_price => rsi_target_price, :current_rsi => current_rsi, :target_rsi => target_rsi, :listed_on => listing_date)
        logger.info("Create Listing values on #{listing.symbol} #{listing.listed_on.to_s(:db)} for #{listing.rsi_target_price} on #{listing.target_rsi}") if logger
      end
    end

    def update_listing(ticker_id, rsi_target_price, current_rsi, threshold, listing_date, options={})
      logger = options[:logger]
      listings = find(:all, :conditions => { :ticker_id => ticker_id, :target_rsi => threshold, :opened_on => nil })
      raise Exception, "More than one watch list entry #{listing.symbol} for the same threhold: #{threshold} encounted!" if listings.length > 1
      listings.each do |listing|
        listing.update_attributes!(:rsi_target_price => rsi_target_price, :current_rsi => current_rsi)
        logger.info("Updated Listing values on #{listing.symbol} #{listing.listed_on.to_s(:db)} to #{listing.rsi_target_price} for RSI #{listing.target_rsi}") if logger
      end
    end

    def lookup_entry(ticker_id, type)
      cond = "ticker_id = #{ticker_id} and " +
        case type
        when :open  : 'opened_on IS NULL'
        when :close : 'opened_on IS NOT NULL'
        else
          raise ArgumentError, "type should be :open or :close"
        end
      find(:all, :conditions => cond)
    end

    def generate_csv()
      csv_string = FasterCSV.generate do |csv|
        csv << ENTRY_HEADING
        WatchList.all(:conditions => 'opened_on is null').each do |position|
          csv << ENTRY_COLUMNS.map { |col| position.send(col) }
        end
      end
    end

    def opened_positions(order=nil)
      WatchList.all(:conditions => 'opened_on is not null', :order => order)
    end

    def purge()
      WatchList.delete_all('closed_on is not null')
      WatchList.all(:conditions => 'tda_positions.exit_date is not null', :include => :tda_position).each { |wl| wl.destroy() }
      WatchList.delete_all(:current_rsi => 0..30)
      WatchList.delete_all(:current_rsi => 33..100)
    end
  end

  def active_entries(options={})
    options.reverse_merge! :order => 'crossed_at desc, (target_ival-current_ival), tickers.symbol', :where => { }
    order = options[:order]
    where = options[:where]
    raise ArgumentError, 'status must be :'
    find :all, :include => :ticker, :conditions => where, :order => order
  end

  def update_open_from_snapshot!(last_bar, curr_rsi, num_samples, last_seq)
    price = last_bar.delete :close
    snap_time = last_bar.delete :time
    attrs = { :price => price, :current_rsi => curr_rsi, :num_samples => num_samples,
              :last_snaptime => snap_time, :last_seq => last_seq, :volume => last_bar[:volume] }
    attrs[:open_crossed_at] = snap_time  if self.open_crossed_at.nil? and curr_rsi >= self.target_rsi
    update_attributes!(attrs.merge(last_bar))
  end
end
