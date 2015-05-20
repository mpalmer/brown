Brown is a "framework for autonomous agents".  That is, essentially, a
high-falutin' way of saying that you can write some code to do some stuff.

More precisely, Brown agents are (typically) small, standalone blocks of
code (encapsulated in a single class) which wait for some stimuli, and then
react to it.  Often, that stimuli is receiving a message (via an AMQP broker
such as [RabbitMQ](http://rabbitmq.org/), however an agent can do anything
it pleases (query a database, watch a filesystem, receive HTTP requests,
whatever) to get stimuli to respond to.


# Installation

It's a gem:

    gem install brown

There's also the wonders of [the Gemfile](http://bundler.io):

    gem 'brown'

If you're the sturdy type that likes to run from git:

    rake build; gem install pkg/brown-<whatever>.gem

Or, if you've eschewed the convenience of Rubygems entirely, then you
presumably know what to do already.


# Usage

To make something an agent, you simply create a subclass of `Brown::Agent`. 
You can then use a simple DSL to define "stimuli", each of which (when
triggered) cause a new instance of the class to be instantiated and a method
(specified by the stimulus) to be invoked in a separate thread.  You can do
arbitrary things to detect stimuli, however there are a number of
pre-defined stimuli you can use to do standard things, like run something
periodically, or process a message on an AMQP queue.

As a very simple example, say you wanted to print `foo` every five seconds. 
(Yes, you *could* do this in a loop, but humour me, would you?)  Using the
built-in `every` stimuli, you could do it like this:

    class FooTicker < Brown::Agent
      every 5 do
        puts "foo"
      end
    end

    FooTicker.run

To demonstrate that each trip of the timer runs in a separate thread, you
could extend this a little:

    class FooTicker < Brown::Agent
      every 5 do
        puts "#{self} is fooing in thread #{Thread.current}"
      end
    end

    FooTicker.run

Every five seconds, it should print out a different `FooTicker` and `Thread`
object.

To show you how `every` is implemented behind the scenes, we can implement
this directly using the generic method, `stimulate`:

    class FooTicker < Brown::Agent
      stimulate :foo do |worker|
        sleep 5
        worker.call
      end
      
      def foo
        puts "#{self} is fooing in thread #{Thread.current}"
      end
    end

    FooTicker.run

What a `stimulate` declaration says is, quite simply:

 * Run this block over and over and over and over again
 * When the block wants a worker to run, it should run `worker.call`
 * I'll then create a new instance of the agent class, and call the method
   name you passed to `stimulate` in a separate thread.

You can pass arguments to the agent method call, by giving them to
`worker.call`.


# Contributing

Bug reports should be sent to the [Github issue
tracker](https://github.com/mpalmer/brown/issues), or
[e-mailed](mailto:theshed+brown@hezmatt.org).  Patches can be sent as a
Github pull request, or [e-mailed](mailto:theshed+brown@hezmatt.org).


# Licence

Unless otherwise stated, everything in this repo is covered by the following
copyright notice:

    Copyright (C) 2015  Matt Palmer <matt@hezmatt.org>

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License version 3, as
    published by the Free Software Foundation.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
