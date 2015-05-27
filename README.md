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


## AMQP publishing / consumption

Since message-based communication is a common pattern amongst cooperating
groups of agents, Brown comes with some helpers to make using AMQP painless.

Firstly, to publish a message, you need to declare a publisher, and then use
it somewhere.  To declare a publisher, you use the `amqp_publisher` method:

    class AmqpPublishingAgent < Brown::Agent
      amqp_publisher :foo
    end

There are a number of options you can add to this call, to set the AMQP
server URL, change the way that the AMQP exchange is declared, and a few
other things.  For all the details on those, see the API docs for
{Brown::Agent.amqp_publisher}.

Once you have declared a publisher, you can send messages through it:

    class AmqpPublishingAgent < Brown::Agent
      amqp_publisher :foo, exchange_name: :foo, exchange_type: :fanout

      every 5 do
        foo.publish("FOO!")
      end
    end

The above example will perform the extremely important task of sending a
message containing the body `FOO!` every five seconds, forever.  Hopefully
you can come up with some more practical uses for this functionality.


### Consuming Messages

Messages being received are just like any other stimulus: you give a block
of code to run when a message is received.  In its simplest form, it looks
like this:

    class AmqpListenerAgent < Brown::Agent
      amqp_listener :foo do |msg|
        logger.info "Received message: #{msg.payload}"
        msg.ack
      end
    end

This example sets up a queue to receive messages send to the exchange `foo`,
and then simply logs every message it receives.  Note the `msg.ack` call;
this is important so that the broker knows that the message has been
received and can send you another message.  If you forget to do this, you'll
only ever receive one message.

The `amqp_listener` method can take a *lot* of different options to
customise how it works; you'll want to read {Brown::Agent.amqp_listener} to
find out all about it.


## Running agents on the command line

The easiest way to run agents "in production" is to use the `brown` command.
Simply pass a list of files which contain subclasses of `Brown::Agent`, and
those classes will be run in individual threads, with automatic restarting.
Convenient, huh?


## Testing

Brown comes with facilities to unit test all of your agents.  Since agents
simply receive stimuli and act on them, testing is quite simple in
principle, but the parallelism inherent in agents can make them hard to test
without some extra helpers.

To enable the additional testing helpers, you must `require
'brown/test_helpers'` somewhere in your testing setup, before you define
your agents.  This will add a bunch of extra methods, defined in
{Brown::TestHelpers} to {Brown::Agent}, which you can then call to examine
certain aspects of the agent (such as `memo?(name)` and
`amqp_publisher?(name)`) as well as send stimuli to the agent and have it
behave appropriately, which you can then make assertions about (either by
examining the new state of the overall system, or through the use of
mocks/spies).

While full documentation for all of the helper methods are available in the
YARD docs for {Brown::TestHelpers}, here are some specific tips for using
them to test certain aspects of your agents in popular testing frameworks.


### RSpec

To test a directly declared stimulus, you don't need to do very much -- you
can just instantiate the agent class and call the method you want:

    class StimulationAgent < Brown::Agent
      stimulate :foo do |worker|
        # Something something
        worker.call
      end
    end

    describe StimulationAgent do
      it "does something" do
        subject.foo

        expect(something).to eq(something_else)
      end
    end

For memos, you can assert that an agent has a given memo quite easily:

    class MemoAgent < Brown::Agent
      memo :blargh do
        "ohai"
      end
    end

    describe MemoAgent do
      it "has the memo" do
        expect(MemoAgent).to have_memo(:blargh)
      end
    end

Then, on top of that, you can assert the value is as you expected, because
memos are accessable at the class level:

    it "has the right value" do
      expect(MemoAgent.blargh(:test)).to eq("ohai")
    end

Or even put it in a let:

    context "value" do
      let(:value) { MemoAgent.blargh(:test) }
    end

Note in the above examples that we passed the special value `:test` to the
call to `.blargh`; that was to let it know that we're definitely testing it
out.  Recall that, ordinarily, a memo that is declared "unsafe" can only be
accessed inside a block passed to the memo method.  For testing purposes,
rather than having to pass a block, we instead just pass in the special
`:test` symbol and it'll let us get the value back.  Note that this won't
work unless you have `require`d `'brown/test_helpers'` *before* you defined
the agent class.

Testing timers is pretty straightforward, too; just trigger away:

    class TimerAgent < Brown::Agent
      every 10 do
        $stderr.puts "Tick tock"
      end
    end

    describe TimerAgent do
      it "goes off on time" do
        expect($stderr).to receive(:info).with("Tick tock")

        TimerAgent.trigger(10)
      end
    end

It is pretty trivial to assert that some particular message was published
via AMQP:

    class PublishTimerAgent < Brown::Agent
      amqp_publisher :time

      every 86400 do
        time.publish "One day more!"
      end
    end

    describe PublishTimerAgent do
      it "publishes to schedule" do
        expect(PublishTimerAgent.time).to receive(:publish).with("One day more!")

        PublishTimerAgent.trigger(86400)
      end
    end

Testing what happens when a particular message gets received isn't much
trickier:

    class ReceiverAgent < Brown::Agent
      amqp_listener "some_exchange" do |msg|
        $stderr.puts "Message: #{msg.payload}"
        msg.ack
      end
    end

    describe ReceiverAgent do
      it "receives the message OK" do
        expect($stderr).to receive(:puts).with("Message: ohai!")

        was_acked = ReceiverAgent.amqp_receive("some_exchange", "ohai!")
        expect(was_acked).to be(true)
      end
    end


### Minitest / other testing frameworks

I don't have any examples for other testing frameworks, because I only use
RSpec.  Contributions on this topic would be greatly appreciated.


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
