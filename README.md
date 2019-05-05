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

    rake install

Or, if you've eschewed the convenience of Rubygems entirely, then you
presumably know what to do already.


# Usage

To make something an agent, you simply create a subclass of `Brown::Agent`.
You can then use a simple DSL to define "stimuli", each of which (when
triggered) cause a new thread to be created, to call the handler method for
that stimulus.  You can do arbitrary things to detect stimuli, however there
are a number of pre-defined stimuli you can use to do standard things, like run
something periodically, or process a message on an AMQP queue.

As a very simple example, say you wanted to print `foo` every five seconds.
(Yes, you *could* do this in a loop, but humour me, would you?)  Using the
built-in `every` stimuli, you could do it like this:

    class FooTicker < Brown::Agent
      every 5 do
        puts "foo"
      end
    end

    FooTicker.new({}).run

To demonstrate that each trip of the timer runs in a separate thread, you
could extend this a little:

    class FooTicker < Brown::Agent
      every 5 do
        puts "#{self} is fooing in thread #{Thread.current}"
      end
    end

    FooTicker.new({}).run

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

    FooTicker.new({}).run

What a `stimulate` declaration says is, quite simply:

 * Run this block over and over and over and over again
 * When the block wants a worker to run, it should run `worker.call`
 * I'll then create a new instance of the agent class, and call the method
   name you passed to `stimulate` in a separate thread.

You can pass arguments to the agent method call, by giving them to
`worker.call`.


## Sharing variables via memos

There is some state you will want to keep for the lifetime of the agent.
Because all stimulus processing happens in multiple threads, there is a helper
available to try and prevent concurrent access to mutable state -- the concept
of "memos".  These are persistent objects, which you access only in a block,
and which wraps your access in a mutex.

To declare them, you simply do:

    class MemoUser < Brown::Agent
      memo(:foo) { Foo.new }
    end

The way this works is that the memo defines an instance method which, the first
time you run it, runs the provided block to create the memo object, which is
then cached.  Thereafter, that cached object is provided, which can be mutated
(though not replaced) safely.

To acquire the lock, and run some code that requires the memoised object, you
pass a block to the memo method, which gets the object passed into it, like this:

    class MemoUser < Brown::Agent
      memo(:foo) { Foo.new }

      every(10) do
        foo do |f|
          f.frob
        end
      end
    end

Here you can see that the instance of `Foo` gets passed into the block given to
the call to `foo`, and then the `Foo#frob` method can be called safe in the
knowledge that nobody else is frobbing the foo at the same time.

The crucial thing to note here is that you *only have the memo lock inside
the block*.  If you were to capture the memo object into a variable outside
the block, and then use it (read *or* write) outside the block, Really Bad
Things can happen.  So **don't do that**.

When you have multiple memos, it is entirely possible that you can end up
deadlocking your agent by acquiring the locks for various memos in different
orders.  Those dining philosophers are always getting themselves in a
muddle.  To prevent this problem, it is highly recommended that you always
acquire the locks for your memos in the same order -- by convention, the
"correct" order to access memos is the order they are placed in the class
definition:

    class MemoUser < Brown::Agent
      memo(:foo) { Foo.new }
      memo(:bar) { Bar.new }

      every(5) do
        # Acquiring a single lock is OK
        foo do |f|
          f.brob
        end
      end

      every(6) do
        # Acquiring a single lock, even a different one, is fine
        bar do |b|
          b.baznicate(b)
        end
      end

      every(7) do
        # This is the right order to acquire nested locks
        foo do |f|
          bar do |b|
            f.frob(b)
          end
        end
      end

      every(8) do
        # This is the WRONG WAY AROUND.  DO NOT DO THIS!
        # YOU WILL GET DEADLOCKS SOONER OR LATER!
        bar do |b|
          foo do |f|
            b.baznicate(f)
          end
        end
      end
    end

Another "gotcha" in the world of memos is that the memoised object itself is
persistent.  When you get the lock, and the memo object comes in via the
argument to your block, that is *a reference* to the memo object.  That
means that reassigning that variable to a new object won't change the value
of the memo object:

    class MemoUser < Brown::Agent
      memo(:now) { Time.now }

      every(5) do
        now do |t|
          puts t
        end
      end

      every(60) do
        now do |t|
          # This will not change the value of the memo object
          t = Time.now
        end
      end
    end

The above code will *always* print the time as at the first time that `now`
was called, even though every minute we *think* we're resetting the memo
value to a new `Time`.

The "hack" around this is to use a single-value array to "contain" the
object that we actually want to periodically replace:

    class MutableMemoUser < Brown::Agent
      memo(:now) { [Time.now] }

      every(5) do
        now do |t|
          puts t[0]
        end
      end

      every(60) do
        now to |t|
          t[0] = Time.now
        end
      end
    end

This example code will print the same time for a minute, before changing to
a new minute.


## AMQP publishing / consumption

Since message-based communication is a common pattern amongst cooperating
groups of agents, Brown comes with some helpers to make using AMQP painless.
To use these helpers, your agent class must `include Brown::Agent::AMQP`.


### Publishing Messages

To publish a message, you need to declare a publisher, and then use
it somewhere.  To declare a publisher, you use the `amqp_publisher` method:

    class AmqpPublishingAgent < Brown::Agent
      include Brown::Agent::AMQP

      amqp_publisher :foo
    end

There are a number of options you can add to this call, to set the AMQP
server URL, change the way that the AMQP exchange is declared, and a few
other things.  For all the details on those, see the API docs for
{Brown::Agent::AMQP.amqp_publisher}.

Once you have declared a publisher, you get a method named after the
publisher, which you can send messages through:

    class AmqpPublishingAgent < Brown::Agent
      include Brown::Agent::AMQP

      amqp_publisher :foo, exchange_name: :foo, exchange_type: :fanout

      every 5 do
        foo.publish("FOO!")
      end
    end

The above example will perform the extremely important task of sending a
message containing the body `FOO!` every five seconds, forever, to the
fanout exchange named `foo`.


### Consuming Messages

Messages being received are just like any other stimulus: you give a block
of code to run when a message is received.  In its simplest form, it looks
like this:

    class AmqpListenerAgent < Brown::Agent
      include Brown::Agent::AMQP

      amqp_listener :foo do |msg|
        logger.info "Received message: #{msg.payload}"
        msg.ack
      end
    end

This example sets up a queue to receive messages sent to the exchange `foo`,
and then logs every message it receives.  Note the `msg.ack` call;
this is important so that the broker knows that the message has been
received and can send you another message.  If you forget to do this, you'll
only ever receive one message.

The `amqp_listener` method can take a *lot* of different options to
customise how it works; you'll want to read {Brown::Agent::AMQP.amqp_listener} to
find out all about it.


## Running agents on the command line

The easiest way to run agents "in production" is to use the `brown` command.
Pass it a file which contains the definition of a subclass of `Brown::Agent`,
and it'll fire off a new agent.  Convenient, huh?


### Metrics, signals, and bears, oh my!

Brown uses the [`service_skeleton`](https://github.com/discourse/service_skeleton) gem
to manage agents, and so you have access to a wide variety of additional (optional)
features, including metrics, log management, and sensible signal handling.  See [the
`service_skeleton` README](https://github.com/discourse/service_skeleton#readme) for details
of all that this fine framework has to offer.


### Running agents in Docke... er, I mean, Moby

Since Moby is the new hawtness, Brown provides a simple base container upon which you can layer
your agent code, and then spawn agents to your heart's content.  As a "simple" example,
let's say you have some agents that need Sequel and Postgres, and your agents live in
the `lib/agents` subdirectory of your repo.  The following `Dockerfile` would build
a new image containing all you need:

    FROM womble/brown

    RUN apt-get update \
     && apt-get -y install libpq-dev libpq5 \
     && gem install pg sequel \
     && apt-get -y purge libpq-dev \
     && apt-get -y autoremove --purge \
     && rm -rf /var/lib/apt/lists/*

    COPY lib/* /usr/local/lib/ruby/2.6.0/
    COPY lib/agents /agents

From there, it is a simple matter of building your new image, and running your agents,
by running a separate docker container from the common image, passing the filename
of each agent as the sole command-line argument:

    docker build -t control .
    docker run -n agent-86 -d control /agents/86.rb
    docker run -n agent-99 -d control /agents/99.rb

... and you're up and running!


## Testing

Brown comes with facilities to write automated tests for your agents.  Since
agents simply receive stimuli and act on them, testing is quite simple in
principle.  However, the inherent parallelism going on behind the scenes can
make agents hard to test without some extra helpers.

To enable the additional testing helpers, you must `require 'brown/test'`
somewhere in your testing setup, before you define your agents.  This will
add a bunch of extra methods, defined in {Brown::TestHelpers}, to
{Brown::Agent}, which you can then call to examine certain aspects of the
agent (such as `memo?(name)` and `amqp_publisher?(name)`) as well as send
stimuli to the agent and have it behave appropriately, which you can then
make assertions about (either by examining the new state of the overall
system, or through the use of mocks/spies).

While full documentation for all of the helper methods are available in the
YARD docs for {Brown::TestHelpers}, here are some specific tips for using
them to test certain aspects of your agents in popular testing frameworks.


### RSpec

To enable additional RSpec-specific test integration (resetting memos at the
end of each test), then **instead** of `require 'brown/test'`, you should
`require 'brown/rspec'` before your agent code is loaded.

To test a directly declared stimulus, you don't need to do very much -- you
can just instantiate the agent class and call the method you want:

    class StimulationAgent < Brown::Agent
      stimulate :foo do |worker|
        # Something something
        worker.call
      end
    end

    describe StimulationAgent do
      let(:agent) { described_class.new({}) }

      it "does something" do
        agent.foo

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
      let(:agent) { described_class.new({}) }

      it "has the memo" do
        expect(agent).to have_memo(:blargh)
      end
    end

Then, on top of that, you can assert the value is as you expected, with the
`#memo_value` method:

    it "has the right value" do
      expect(agent.memo_value(:blargh)).to eq("ohai")
    end

Or even put it in a let:

    context "value" do
      let(:value) { agent.memo_value(:blargh) }
    end

Testing timers is pretty straightforward, too; just trigger away:

    class TimerAgent < Brown::Agent
      every 5 do
        $stderr.puts "Tick tock"
      end

      every 10 do
        $stderr.puts "BONG"
      end

      every 10 do
        $stderr.puts "CRASH!"
      end
    end

    describe TimerAgent do
      let(:agent) { described_class.mew({}) }

      it "goes off on time" do
        expect($stderr).to_not receive(:info).with("Tick tock")
        expect($stderr).to receive(:info).with("BONG")
        expect($stderr).to receive(:info).with("CRASH!")

        TimerAgent.trigger(10)
      end
    end

Calling `#trigger` calls all of the `every` stimuli which run every number
of seconds given.

It is pretty trivial to assert that some particular message was published
via AMQP:

    class PublishTimerAgent < Brown::Agent
      include Brown::Agent::AMQP

      amqp_publisher :time

      every 86400 do
        time.publish "One day more!"
      end
    end

    describe PublishTimerAgent do
      let(:agent) { described_class.new({}) }

      it "publishes to schedule" do
        expect(agent.time).to receive(:publish).with("One day more!")

        agent.trigger(86400)
      end
    end

Testing what happens when a particular message gets received isn't much
trickier:

    class ReceiverAgent < Brown::Agent
      include Brown::Agent::AMQP

      amqp_listener "some_exchange" do |msg|
        $stderr.puts "Message: #{msg.payload}"
        msg.ack
      end
    end

    describe ReceiverAgent do
      let(:agent) { described_class.new({}) }

      it "receives the message OK" do
        expect($stderr).to receive(:puts).with("Message: ohai!")

        was_acked = agent.amqp_receive("some_exchange", "ohai!")
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
