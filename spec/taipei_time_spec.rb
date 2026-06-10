# frozen_string_literal: true

require_relative 'spec_helper'

describe SecureBidding::TaipeiTime do
  it 'parses datetime-local values as Taiwan time' do
    time = SecureBidding::TaipeiTime.parse('2026-06-10T22:30')
    _(time.iso8601).must_equal '2026-06-10T22:30:00+08:00'
  end

  it 'keeps explicit offsets intact' do
    time = SecureBidding::TaipeiTime.parse('2026-06-10T14:30:00Z')
    _(time.utc.iso8601).must_equal '2026-06-10T14:30:00Z'
  end
end
