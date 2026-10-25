require 'rails_helper'

RSpec.describe Outsider::Voice::PhoneNumber do
  it 'turns what the operator and the seller type into DDD + number' do
    expect(described_class.national('062 99999-8888')).to eq('62999998888')
    expect(described_class.national('+55 62 3234-5678')).to eq('6232345678')
    expect(described_class.national('5562999998888')).to eq('62999998888')
    expect(described_class.national('0800 123 4567')).to eq('08001234567')
    expect(described_class.national('4004-1234')).to eq('40041234')
  end

  it 'refuses international, premium and short numbers' do
    expect(described_class.national('+1 415 555 0100')).to be_nil
    expect(described_class.national('0900 123 4567')).to be_nil
    expect(described_class.national('190')).to be_nil
  end

  it 'compares numbers with or without the extra 9' do
    expect(described_class.same?('+5562999998888', '6299998888')).to be(true)
    expect(described_class.same?('+5562999998888', '1199998888')).to be(false)
  end

  it 'finds the contact by phone' do
    account = create(:account)
    contact = create(:contact, account: account, phone_number: '+5562999998888')

    expect(described_class.find_contact(account, '062 9999-8888')).to eq(contact)
  end
end
