#--
# Copyright (c) 2008-20010 Kevin Patrick Nolan
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++
#--
# Copyright (c) 2008-20010 Kevin Patrick Nolan
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++
# Author::    Mohammad A. Ali  (mailto:oldmoe@gmail.com)
# Copyright:: Copyright (c) 2008 eSpace, Inc.
# License::   Distributes under the same terms as Ruby

require 'fiber'

class Fiber
  
  #Attribute Reference--Returns the value of a fiber-local variable, using
  #either a symbol or a string name. If the specified variable does not exist,
  #returns nil.
  def [](key)
    local_fiber_variables[key]
  end
  
  #Attribute Assignment--Sets or creates the value of a fiber-local variable,
  #using either a symbol or a string. See also Fiber#[].
  def []=(key,value)
    local_fiber_variables[key] = value
  end
  
  private
  
  def local_fiber_variables
    @local_fiber_variables ||= {}
  end
end

class FiberPool

  # gives access to the currently free fibers
  attr_reader :fibers
  attr_reader :busy_fibers

  # Code can register a proc with this FiberPool to be called
  # every time a Fiber is finished.  Good for releasing resources
  # like ActiveRecord database connections.
  attr_accessor :generic_callbacks

  # Prepare a list of fibers that are able to run different blocks of code
  # every time. Once a fiber is done with its block, it attempts to fetch
  # another one from the queue
  def initialize(count = 100)
    @fibers,@busy_fibers,@queue,@generic_callbacks = [],{},[],[]
    count.times do |i|
      fiber = Fiber.new do |block|
        loop do
          block.call
          # callbacks are called in a reverse order, much like c++ destructor
          Fiber.current[:callbacks].pop.call while Fiber.current[:callbacks].length > 0
          generic_callbacks.each do |cb|
            cb.call
          end
          unless @queue.empty?
            block = @queue.shift
          else
            @busy_fibers.delete(Fiber.current.object_id)
            @fibers << Fiber.current
            block = Fiber.yield
          end
        end
      end
      fiber[:callbacks] = []
      fiber[:em_keys] = []
      @fibers << fiber
    end
  end

  # If there is an available fiber use it, otherwise, leave it to linger
  # in a queue
  def spawn(&block)
    if fiber = @fibers.shift
      fiber[:callbacks] = []
      @busy_fibers[fiber.object_id] = fiber
      fiber.resume(block)
    else
      @queue << block
    end
    self # we are keen on hiding our queue
  end

end
