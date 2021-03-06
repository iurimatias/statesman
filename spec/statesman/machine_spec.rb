require "spec_helper"

describe Statesman::Machine do
  let(:machine) { Class.new { include Statesman::Machine } }
  let(:my_model) { Class.new { attr_accessor :current_state }.new }

  describe ".state" do
    before { machine.state(:x) }
    before { machine.state(:y) }
    specify { expect(machine.states).to eq(%w(x y)) }

    context "initial" do
      before { machine.state(:x, initial: true) }
      specify { expect(machine.initial_state).to eq("x") }

      context "when an initial state is already defined" do
        it "raises an error" do
          expect do
            machine.state(:y, initial: true)
          end.to raise_error(Statesman::InvalidStateError)
        end
      end
    end
  end

  describe ".transition" do
    before do
      machine.class_eval do
        state :x
        state :y
        state :z
      end
    end

    context "given neither a 'from' nor a 'to' state" do
      it "raises an error" do
        expect do
          machine.transition
        end.to raise_error(Statesman::InvalidStateError)
      end
    end

    context "given an invalid 'from' state" do
      it "raises an error" do
        expect do
          machine.transition(from: :a, to: :x)
        end.to raise_error(Statesman::InvalidStateError)
      end
    end

    context "given an invalid 'to' state" do
      it "raises an error" do
        expect do
          machine.transition(from: :x, to: :a)
        end.to raise_error(Statesman::InvalidStateError)
      end
    end

    context "valid 'from' and 'to' states" do
      it "records the transition" do
        machine.transition(from: :x, to: :y)
        machine.transition(from: :x, to: :z)
        expect(machine.successors).to eq("x" => %w(y z))
      end
    end
  end

  describe ".validate_callback_condition" do
    before do
      machine.class_eval do
        state :x
        state :y
        state :z
        transition from: :x, to: :y
        transition from: :y, to: :z
      end
    end

    context "with a terminal 'from' state" do
      it "raises an exception" do
        expect do
          machine.validate_callback_condition(from: :z, to: :y)
        end.to raise_error(Statesman::InvalidTransitionError)
      end
    end

    context "with an initial 'to' state" do
      it "raises an exception" do
        expect do
          machine.validate_callback_condition(from: :y, to: :x)
        end.to raise_error(Statesman::InvalidTransitionError)
      end
    end

    context "with an invalid transition" do
      it "raises an exception" do
        expect do
          machine.validate_callback_condition(from: :x, to: :z)
        end.to raise_error(Statesman::InvalidTransitionError)
      end
    end

    context "with any states" do
      it "does not raise an exception" do
        expect { machine.validate_callback_condition }.to_not raise_error
      end
    end

    context "with a valid transition" do
      it "does not raise an exception" do
        expect do
          machine.validate_callback_condition(from: :x, to: :y)
        end.to_not raise_error
      end
    end
  end

  shared_examples "a callback store" do |assignment_method, callback_store|
    before do
      machine.class_eval do
        state :x, initial: true
        state :y
        transition from: :x, to: :y
      end
    end

    it "stores callbacks" do
      expect do
        machine.send(assignment_method) {}
      end.to change(machine.callbacks[callback_store], :count).by(1)
    end

    it "stores callback instances" do
      machine.send(assignment_method) {}
      machine.callbacks[callback_store].each do |callback|
        expect(callback).to be_a(Statesman::Callback)
      end
    end

    context "with invalid states" do
      it "raises an exception when both are invalid" do
        expect do
          machine.send(assignment_method, from: :foo, to: :bar) {}
        end.to raise_error(Statesman::InvalidStateError)
      end

      it "raises an exception with a terminal from state and nil to state" do
        expect do
          machine.send(assignment_method, from: :y) {}
        end.to raise_error(Statesman::InvalidTransitionError)
      end

      it "raises an exception with an initial to state and nil from state" do
        expect do
          machine.send(assignment_method, to: :x) {}
        end.to raise_error(Statesman::InvalidTransitionError)
      end
    end

    context "with validate_states" do
      it "allows a nil from state" do
        expect do
          machine.send(assignment_method, to: :y) {}
        end.to_not raise_error
      end

      it "allows a nil to state" do
        expect do
          machine.send(assignment_method, from: :x) {}
        end.to_not raise_error
      end
    end
  end

  describe ".before_transition" do
    it_behaves_like "a callback store", :before_transition, :before
  end

  describe ".after_transition" do
    it_behaves_like "a callback store", :after_transition, :after
  end

  describe ".guard_transition" do
    it_behaves_like "a callback store", :guard_transition, :guards
  end

  describe "#initialize" do
    it "accepts an object to manipulate" do
      machine_instance = machine.new(my_model)
      expect(machine_instance.object).to be(my_model)
    end

    context "transition class" do
      it "sets a default" do
        Statesman.storage_adapter.should_receive(:new).once
          .with(Statesman::Adapters::MemoryTransition, my_model, anything)
        machine.new(my_model)
      end

      it "sets the passed class" do
        my_transition_class = Class.new
        Statesman.storage_adapter.should_receive(:new).once
          .with(my_transition_class, my_model, anything)
        machine.new(my_model, transition_class: my_transition_class)
      end

      it "falls back to Memory without transaction_class" do
        Statesman.stub(:storage_adapter).and_return(Class.new)
        Statesman::Adapters::Memory.should_receive(:new).once
          .with(Statesman::Adapters::MemoryTransition, my_model, anything)
        machine.new(my_model)
      end
    end
  end

  describe "#after_initialize" do
    it "is called after initialize" do
      machine.class_eval do
        def after_initialize; end
      end
      expect_any_instance_of(machine).to receive :after_initialize
      machine.new(my_model)
    end
  end

  describe "#current_state" do
    before do
      machine.class_eval do
        state :x, initial: true
        state :y
        state :z
        transition from: :x, to: :y
        transition from: :y, to: :z
      end
    end

    let(:instance) { machine.new(my_model) }
    subject { instance.current_state }

    context "with no transitions" do
      it { should eq(machine.initial_state) }
    end

    context "with multiple transitions" do
      before do
        instance.transition_to!(:y)
        instance.transition_to!(:z)
      end

      it { should eq("z") }
    end
  end

  describe "#allowed_transitions" do
    before do
      machine.class_eval do
        state :x, initial: true
        state :y
        state :z
        transition from: :x, to: [:y, :z]
        transition from: :y, to: :z
      end
    end

    let(:instance) { machine.new(my_model) }
    subject { instance.allowed_transitions }

    context "with multiple possible states" do
      it { should eq(%w(y z)) }
    end

    context "with one possible state" do
      before do
        instance.transition_to!(:y)
      end

      it { should eq(['z']) }
    end

    context "with no possible transitions" do
      before do
        instance.transition_to!(:z)
      end

      it { should eq([]) }
    end
  end

  describe "#last_transition" do
    let(:instance) { machine.new(my_model) }
    let(:last_action) { "Whatever" }

    it "delegates to the storage adapter" do
      Statesman.storage_adapter.any_instance.should_receive(:last).once
        .and_return(last_action)
      expect(instance.last_transition).to be(last_action)
    end
  end

  describe "#can_transition_to?" do
    before do
      machine.class_eval do
        state :x, initial: true
        state :y
        state :z
        transition from: :x, to: :y
        transition from: :y, to: :z
      end
    end

    let(:instance) { machine.new(my_model) }
    subject { instance.can_transition_to?(new_state) }

    context "when the transition is invalid" do
      context "with an initial to state" do
        let(:new_state) { :x }
        it { should be_false }
      end

      context "with a terminal from state" do
        before { instance.transition_to!(:y) }
        let(:new_state) { :y }
        it { should be_false }
      end

      context "and is guarded" do
        let(:guard_cb) { -> { false } }
        let(:new_state) { :z }
        before { machine.guard_transition(to: new_state, &guard_cb) }

        it "does not fire guard" do
          guard_cb.should_not_receive(:call)
          should be_false
        end
      end
    end

    context "when the transition valid" do
      let(:new_state) { :y }
      it { should be_true }

      context "but it has a failing guard" do
        before { machine.guard_transition(to: :y) { false } }
        it { should be_false }
      end
    end
  end

  describe "#transition_to!" do
    before do
      machine.class_eval do
        state :x, initial: true
        state :y
        state :z
        transition from: :x, to: :y
        transition from: :y, to: :z
      end
    end

    let(:instance) { machine.new(my_model) }

    context "when the state cannot be transitioned to" do
      it "raises an error" do
        expect do
          instance.transition_to!(:z)
        end.to raise_error(Statesman::TransitionFailedError)
      end
    end

    context "when the state can be transitioned to" do
      it "changes state" do
        instance.transition_to!(:y)
        expect(instance.current_state).to eq("y")
      end

      it "creates a new transition object" do
        expect do
          instance.transition_to!(:y)
        end.to change(instance.history, :count).by(1)

        expect(instance.history.first)
          .to be_a(Statesman::Adapters::MemoryTransition)
        expect(instance.history.first.to_state).to eq("y")
      end

      it "sends metadata to the transition object" do
        meta = { "my" => "hash" }
        instance.transition_to!(:y, meta)
        expect(instance.history.first.metadata).to eq(meta)
      end

      it "returns true" do
        expect(instance.transition_to!(:y)).to be_true
      end

      context "with a guard" do
        let(:result) { true }
        let(:guard_cb) { ->(*args) { result } }
        before { machine.guard_transition(from: :x, to: :y, &guard_cb) }

        context "and an object to act on" do
          let(:instance) { machine.new(my_model) }

          it "passes the object to the guard" do
            guard_cb.should_receive(:call).once
              .with(my_model, instance.last_transition, nil).and_return(true)
            instance.transition_to!(:y)
          end
        end

        context "which passes" do
          it "changes state" do
            instance.transition_to!(:y)
            expect(instance.current_state).to eq("y")
          end
        end

        context "which fails" do
          let(:result) { false }

          it "raises an exception" do
            expect do
              instance.transition_to!(:y)
            end.to raise_error(Statesman::GuardFailedError)
          end
        end
      end
    end
  end

  describe "#transition_to" do
    let(:instance) { machine.new(my_model) }
    let(:metadata) { { some: :metadata } }
    subject { instance.transition_to(:some_state, metadata) }

    context "when it is succesful" do
      before do
        instance.should_receive(:transition_to!).once
          .with(:some_state, metadata).and_return(:some_state)
      end
      it { should be(:some_state) }
    end

    context "when it is unsuccesful" do
      before do
        instance.stub(:transition_to!).and_raise(Statesman::GuardFailedError)
      end
      it { should be_false }
    end

    context "when a non statesman exception is raised" do
      before do
        instance.stub(:transition_to!).and_raise(RuntimeError,
                                                 'user defined exception')
      end

      it "should not rescue the exception" do
        expectation = expect do
          instance.transition_to(:some_state, metadata)
        end

        expectation.to raise_error(RuntimeError, 'user defined exception')
      end
    end
  end

  shared_examples "a callback filter" do |definer, phase|
    before do
      machine.class_eval do
        state :x
        state :y
        state :z
        transition from: :x, to: :y
        transition from: :y, to: :z
      end
    end

    let(:instance) { machine.new(my_model) }
    let(:callbacks) { instance.send(:callbacks_for, phase, from: :x, to: :y) }

    context "with no defined callbacks" do
      specify { expect(callbacks).to eq([]) }
    end

    context "with defined callbacks" do
      let(:callback_1) { -> { "Hi" } }
      let(:callback_2) { -> { "Bye" } }

      before do
        machine.send(definer, from: :x, to: :y, &callback_1)
        machine.send(definer, from: :y, to: :z, &callback_2)
      end

      it "contains the relevant callback" do
        expect(callbacks.map(&:callback)).to include(callback_1)
      end

      it "does not contain the irrelevant callback" do
        expect(callbacks.map(&:callback)).to_not include(callback_2)
      end
    end
  end

  describe "#guards_for" do
    it_behaves_like "a callback filter", :guard_transition, :guards
  end

  describe "#before_callbacks_for" do
    it_behaves_like "a callback filter", :before_transition,
                    :before
  end

  describe "#after_callbacks_for" do
    it_behaves_like "a callback filter", :after_transition,
                    :after
  end

  describe "#event" do
    before do
      machine.class_eval do
        state :x, initial: true
        state :y
        state :z

        event :event_1 do
          transition from: :x, to: :y
        end

        event :event_2 do
          transition from: :y, to: :z
        end
      end
    end

    let(:instance) { machine.new(my_model) }

    context "when the state cannot be transitioned to" do
      it "raises an error" do
        expect do
          instance.trigger!(:event_2)
        end.to raise_error(Statesman::TransitionFailedError)
      end
    end

    context "when the state can be transitioned to" do
      it "changes state" do
        instance.trigger!(:event_1)
        expect(instance.current_state).to eq("y")
      end

      it "creates a new transition object" do
        expect do
          instance.trigger!(:event_1)
        end.to change(instance.history, :count).by(1)

        expect(instance.history.first)
          .to be_a(Statesman::Adapters::MemoryTransition)
        expect(instance.history.first.to_state).to eq("y")
      end

      it "sends metadata to the transition object" do
        meta = { "my" => "hash" }
        instance.trigger!(:event_1, meta)
        expect(instance.history.first.metadata).to eq(meta)
      end

      it "returns true" do
        expect(instance.trigger!(:event_1)).to be_true
      end

      context "with a guard" do
        let(:result) { true }
        let(:guard_cb) { ->(*args) { result } }
        before { machine.guard_transition(from: :x, to: :y, &guard_cb) }

        context "and an object to act on" do
          let(:instance) { machine.new(my_model) }

          it "passes the object to the guard" do
            guard_cb.should_receive(:call).once
              .with(my_model, instance.last_transition, nil).and_return(true)
            instance.trigger!(:event_1)
          end
        end

        context "which passes" do
          it "changes state" do
            instance.trigger!(:event_1)
            expect(instance.current_state).to eq("y")
          end
        end

        context "which fails" do
          let(:result) { false }

          it "raises an exception" do
            expect do
              instance.trigger!(:event_1)
            end.to raise_error(Statesman::GuardFailedError)
          end
        end
      end
    end

  end

  describe "#available_events" do
    before do
      machine.class_eval do
        state :x, initial: true
        state :y
        state :z

        event :event_1 do
          transition from: :x, to: :y
        end

        event :event_2 do
          transition from: :y, to: :z
        end

        event :event_3 do
          transition from: :x, to: :y
          transition from: :y, to: :x
        end
      end
    end

    let(:instance) { machine.new(my_model) }
    it "should return list of available events for the current state" do
      expect(instance.available_events).to eq([:event_1, :event_3])
      instance.trigger!(:event_1)
      expect(instance.available_events).to eq([:event_2, :event_3])
    end
  end

end
