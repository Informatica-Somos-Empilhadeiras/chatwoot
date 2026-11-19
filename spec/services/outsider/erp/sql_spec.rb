require 'rails_helper'

RSpec.describe Outsider::Erp::Sql do
  describe '.ident' do
    it 'accepts only the restricted company/bank format' do
      expect(described_class.ident('somosemp')).to eq('somosemp')
      expect { described_class.ident('somos emp') }.to raise_error(ArgumentError)
      expect { described_class.ident('Somos; DROP') }.to raise_error(ArgumentError)
      expect { described_class.ident('a') }.to raise_error(ArgumentError)
    end
  end

  describe '.str' do
    it 'escapes quotes, backslashes and control chars and quotes the literal' do
      expect(described_class.str("O'Brien")).to eq("'O\\'Brien'")
      expect(described_class.str('a\\b')).to eq("'a\\\\b'")
      expect(described_class.str("x\ny")).to eq("'x\\ny'")
    end

    it 'turns nil and empty into NULL' do
      expect(described_class.str(nil)).to eq('NULL')
      expect(described_class.str('')).to eq('NULL')
    end

    it 'neutralizes an injection attempt as a plain literal' do
      expect(described_class.str("'); DROP TABLE Orcamento; --")).to eq("'\\'); DROP TABLE Orcamento; --'")
    end
  end

  describe '.int' do
    it 'keeps integers and rejects anything else as NULL' do
      expect(described_class.int('42')).to eq('42')
      expect(described_class.int(7)).to eq('7')
      expect(described_class.int('1 OR 1=1')).to eq('NULL')
      expect(described_class.int(nil)).to eq('NULL')
    end
  end

  describe '.dec' do
    it 'formats decimals with a dot and no scientific notation' do
      expect(described_class.dec('1234.5')).to eq('1234.5')
      expect(described_class.dec(0)).to eq('0.0')
      expect(described_class.dec(nil)).to eq('0')
      expect(described_class.dec('abc')).to eq('0')
    end
  end

  describe '.date' do
    it 'formats dates and rejects junk as NULL' do
      expect(described_class.date(Date.new(2026, 11, 20))).to eq("'2026-11-20'")
      expect(described_class.date('2026-11-20')).to eq("'2026-11-20'")
      expect(described_class.date(nil)).to eq('NULL')
      expect(described_class.date('not a date')).to eq('NULL')
    end
  end
end
