require 'rails_helper'

RSpec.describe Outsider::Voice::Region do
  it 'finds the state by the area code and tells mobile from landline' do
    expect(described_class.of('+5562998100003')).to eq(ddd: '62', state: 'GO', mobile: true)
    expect(described_class.of('1132001122')).to eq(ddd: '11', state: 'SP', mobile: false)
    expect(described_class.of('064 3200-1122')).to include(ddd: '64', state: 'GO')
  end

  it 'puts numbers from other countries in the international box' do
    expect(described_class.of('+15551234567')).to eq(ddd: nil, state: 'INT', mobile: false)
  end

  it 'has no place for short numbers and 0800' do
    expect(described_class.of('201')).to be_nil
    expect(described_class.of('08001234567')).to be_nil
    expect(described_class.special?('08001234567')).to be(true)
  end
end
