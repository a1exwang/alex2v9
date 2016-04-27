infile = ARGV[0]
outfile = ARGV[1]

elf_header = `readelf -h #{infile}`
section_headers = `objdump -h #{infile}`
section_content = `llvm-objdump -arch=alex -s #{infile}`

# parse entry point
raise 'readelf format error' unless elf_header =~ /Entry point address:\s+0x([0-9]+)$/i
entry_point = $1.to_i(16)

# parse text, bss, data section file offsets and vmas
def parse_section_header(str, section_name)
  return nil unless str =~ /\.#{section_name}\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/
  {
      size: $1.to_i(16),
      vma:  $2.to_i(16),
      lma:  $3.to_i(16),
      file_off: $4.to_i(16)
  }
end

text = parse_section_header(section_headers, 'text')
raise 'text section headers error' unless text
rodata = parse_section_header(section_headers, 'rodata')
bss = parse_section_header(section_headers, 'bss')
data = parse_section_header(section_headers, 'data')

# parse section content
def hex_str_to_binary(hexstr)
  raise 'hex string format error' unless hexstr.size % 2 == 0
  ret = ''
  (hexstr.size/2).times do |i|
    ret += [hexstr[(2*i)..(2*i+1)].to_i(16)].pack('C')
  end
  ret
end

def parse_section_content(str, section_name)
  started = false
  content = ''
  str.split("\n").each do |line|
    if line =~ /Contents of section \.(\w+):/
      name = $1
      if name == section_name
        started = true
      elsif started && name != section_name
        break
      end
    end

    if started && line =~ /^ \d+/
      line_data_array = line.split(' ')[1..-1]
      line_data_array.reject! { |l| ! (l =~ /^[0-9a-f]+$/i)}
      line_data = line_data_array.join('')
      content += hex_str_to_binary(line_data)
    end
  end
  content
end
#puts section_content
text[:content] = parse_section_content(section_content, 'text')
data[:content] = parse_section_content(section_content, 'data') if data
rodata[:content] = parse_section_content(section_content, 'rodata') if rodata

def fill_v9_header(file_data, entry_point, data_offset)
  file_data[0...4]  = [0xC0DEF00D].pack('L')
  file_data[8...12] = [entry_point].pack('L')
  file_data[12...16] = [data_offset].pack('L')
  16
end
def fill_section(file_data, section)
  if section[:content]
    file_data[section[:vma]...(section[:vma]+section[:size])] =
      section[:content]
  end
end

last_section = ([text, bss, data, rodata].compact.sort_by { |section| section[:vma] }).last
file_size = last_section[:vma] + last_section[:size]

file_data = ([0]*file_size).pack('C*')

fill_v9_header(file_data, entry_point, text[:vma]+text[:size])
fill_section(file_data, text)
fill_section(file_data, rodata) if rodata
fill_section(file_data, data) if data

File.write(outfile, file_data)