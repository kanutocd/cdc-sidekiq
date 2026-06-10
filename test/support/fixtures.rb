# frozen_string_literal: true

class FakeResult
  attr_reader :value

  def initialize(value, failure: false)
    @value = value
    @failure = failure
  end

  def failure?
    @failure
  end
end

class RecordingProcessor
  attr_reader :items

  def initialize
    @items = []
  end

  def process(item)
    @items << item
    FakeResult.new(item)
  end
end

class FailingProcessor
  def process(item)
    FakeResult.new(item, failure: true)
  end
end
