# OUTSIDER: lê arquivos de dentro de um .docx, .xlsx ou .pptx (que são zip) sem gem nova: só o diretório do zip e o
# Zlib do Ruby. Cada arquivo lido tem limite de tamanho, para um zip malicioso não estourar a memória. Sem ZIP64
# (documentos do Office com mais de 4 GB não interessam aqui).
class Outsider::ZipEntries
  MAX_ENTRY = 8.megabytes
  CHUNK = 16_384
  LOCAL = "PK\x03\x04".b
  CENTRAL = "PK\x01\x02".b
  ENDING = "PK\x05\x06".b

  def initialize(data)
    @data = data.to_s.b
    @entries = read_directory
  end

  def names
    @entries.keys
  end

  # conteúdo cru (imagem) ou nil
  def read(name)
    entry = @entries[name]
    return nil unless entry && entry[:size] <= MAX_ENTRY && @data.byteslice(entry[:offset], 4) == LOCAL

    name_length, extra_length = @data.byteslice(entry[:offset] + 26, 4).unpack('vv')
    raw = @data.byteslice(entry[:offset] + 30 + name_length + extra_length, entry[:compressed]).to_s
    case entry[:method]
    when 0 then raw
    when 8 then inflate(raw)
    end
  rescue Zlib::Error, ArgumentError, TypeError
    nil
  end

  # XML de dentro do documento, como texto
  def text(name)
    read(name)&.force_encoding('UTF-8')&.scrub('')
  end

  private

  def inflate(raw)
    stream = Zlib::Inflate.new(-Zlib::MAX_WBITS)
    out = ''.b
    position = 0
    while position < raw.bytesize
      out << stream.inflate(raw.byteslice(position, CHUNK))
      return nil if out.bytesize > MAX_ENTRY

      position += CHUNK
    end
    out
  ensure
    stream&.close
  end

  # fim do zip (End Of Central Directory) e a lista de arquivos: nome => método, tamanhos e onde começa
  def read_directory
    tail_start = [@data.bytesize - 65_557, 0].max
    found = @data.byteslice(tail_start, @data.bytesize - tail_start).to_s.rindex(ENDING)
    return {} unless found

    count, _size, position = @data.byteslice(tail_start + found + 10, 10).to_s.unpack('vVV')
    entries = {}
    count.to_i.times do
      name, entry, position = central_entry(position)
      break unless name

      entries[name] = entry
    end
    entries
  rescue ArgumentError, TypeError, NoMethodError
    {}
  end

  def central_entry(position)
    return nil unless @data.byteslice(position, 4) == CENTRAL

    method = @data.byteslice(position + 10, 2).unpack1('v')
    compressed, size, name_length, extra_length, comment_length = @data.byteslice(position + 20, 14).unpack('VVvvv')
    name = @data.byteslice(position + 46, name_length).to_s.dup.force_encoding('UTF-8')
    offset = @data.byteslice(position + 42, 4).unpack1('V')
    [name, { method: method, compressed: compressed, size: size, offset: offset },
     position + 46 + name_length + extra_length + comment_length]
  end
end
