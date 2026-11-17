# OUTSIDER: .zip escrito aos pedaços enquanto os arquivos chegam (sem guardar nada em disco nem na memória): cada arquivo
# vai "armazenado" (sem compactar; fotos e vídeos já vêm compactados), com o CRC e o tamanho no fim de cada um (bit 3) e
# o índice no final. Nomes em UTF-8 (bit 11), repetidos ganham " (2)". Sem Zip64: para em LIMIT (pouco menos de 4 GB).
#   zip = Outsider::ZipStream.new(->(bytes) { stream.write(bytes) })
#   zip.add('foto.jpg') { |write| write.call(pedaço) }
#   zip.finish
class Outsider::ZipStream
  LIMIT = 4.gigabytes - 64.megabytes
  FLAGS = 0x0008 | 0x0800
  VERSION = 20

  attr_reader :offset

  def initialize(writer, time: Time.current)
    @writer = writer
    @offset = 0
    @entries = []
    @names = Hash.new(0)
    @dos_time, @dos_date = dos(time)
  end

  def full?
    @offset >= LIMIT
  end

  # devolve quantos bytes o arquivo teve
  def add(name)
    raw = unique(clean(name)).encode('UTF-8').b
    start = @offset
    write([0x04034b50, VERSION, FLAGS, 0, @dos_time, @dos_date, 0, 0, 0, raw.bytesize, 0].pack('VvvvvvVVVvv') + raw)
    crc = 0
    size = 0
    begin
      yield(lambda do |chunk|
        chunk = chunk.to_s.b
        raise ArgumentError, 'zip too big' if size + chunk.bytesize > LIMIT

        crc = Zlib.crc32(chunk, crc)
        size += chunk.bytesize
        write(chunk)
      end)
    ensure
      # mesmo se o download parar no meio, a entrada fica coerente (o arquivo sai cortado e o motivo vai no LEIA-ME)
      write([0x08074b50, crc, size, size].pack('VVVV'))
      @entries << { name: raw, crc: crc, size: size, offset: start }
    end
    size
  end

  def finish
    start = @offset
    @entries.each do |entry|
      write([0x02014b50, VERSION, VERSION, FLAGS, 0, @dos_time, @dos_date, entry[:crc], entry[:size], entry[:size],
             entry[:name].bytesize, 0, 0, 0, 0, 0, entry[:offset]].pack('VvvvvvvVVVvvvvvVV') + entry[:name])
    end
    write([0x06054b50, 0, 0, @entries.size, @entries.size, @offset - start, start, 0].pack('VvvvvVVv'))
  end

  private

  def write(bytes)
    @writer.call(bytes)
    @offset += bytes.bytesize
  end

  def clean(name)
    value = name.to_s.unicode_normalize(:nfc).tr('/\\:*?"<>|', '_').gsub(/[[:cntrl:]]/, '').strip
    value = 'arquivo' if value.blank? || value.match?(/\A\.+\z/)
    value.first(180)
  end

  def unique(name)
    key = name.downcase
    @names[key] += 1
    return name if @names[key] == 1

    ext = File.extname(name)
    "#{File.basename(name, ext)} (#{@names[key]})#{ext}"
  end

  def dos(time)
    local = time.in_time_zone
    [(local.hour << 11) | (local.min << 5) | (local.sec / 2), ((local.year - 1980) << 9) | (local.month << 5) | local.day]
  end
end
