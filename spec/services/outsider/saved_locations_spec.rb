require 'rails_helper'

RSpec.describe Outsider::SavedLocations do
  let(:account) { create(:account) }
  let(:saved) { described_class.new(account) }

  it 'adds and removes places in the account without touching other attributes' do
    account.update!(internal_attributes: { 'other' => 'kept' })

    first = saved.create(name: ' Matriz ', address: 'Goiânia', latitude: '-16.68', longitude: '-49.25')
    second = saved.create(name: 'Filial', latitude: -15.79, longitude: -47.88)

    expect(first).to eq('id' => 1, 'name' => 'Matriz', 'address' => 'Goiânia', 'latitude' => -16.68, 'longitude' => -49.25)
    expect(second['id']).to eq(2)
    expect(described_class.new(account.reload).all.pluck('name')).to eq(%w[Matriz Filial])

    saved.destroy(1)
    account.reload
    expect(described_class.new(account).all.pluck('name')).to eq(%w[Filial])
    expect(account.internal_attributes['other']).to eq('kept')
  end

  it 'refuses places without name or with bad coordinates, and unknown ids' do
    expect { saved.create(name: '', latitude: 1, longitude: 1) }.to raise_error(described_class::Invalid, 'missing_name')
    expect { saved.create(name: 'X', latitude: 100, longitude: 1) }.to raise_error(described_class::Invalid, 'invalid_coordinates')
    expect { saved.destroy(99) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'limits the list' do
    stub_const('Outsider::SavedLocations::MAX', 1)
    saved.create(name: 'A', latitude: 1, longitude: 1)

    expect { saved.create(name: 'B', latitude: 1, longitude: 1) }.to raise_error(described_class::Invalid, 'too_many_locations')
  end
end
