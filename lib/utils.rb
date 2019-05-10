require 'zip'

# NOTE: this file is not required while running your code
# the patched classes are used only in tests and tools
class String
  def camelize
    split('_').collect do |word|
      word[0] = word[0].upcase
      word
    end.join
  end

  def underscore
    gsub(/([A-Z]+)([0-9]|[A-Z]|\z)/){"#{$1.capitalize}#{$2}"}
      .gsub(/(.)([A-Z])/, '\1_\2')
      .downcase
  end

  def dasherize
    underscore.gsub('_', '-')
  end
end

class Object
  def symbolize_keys
    case self
    when Hash
      hash = {}
      each {|k, v| hash[k.to_sym] = v.symbolize_keys}
      hash
    when Array
      map {|x| x.symbolize_keys}
    else
      self
    end
  end


  def stringify_keys
    case self
    when Hash
      hash = {}
      each {|k, v| hash[k.to_s] = v.stringify_keys}
      hash
    when Array
      map {|x| x.stringify_keys}
    else
      self
    end
  end
end

module Utils
  module_function

  def load_json(path)
    JSON.parse(File.read(path))
  end

  def checksum(dir)
    files = Dir["#{dir}/**/*"].reject{|f| File.directory?(f)}
    content = files.map{|f| File.read(f)}.join
    Digest::MD5.hexdigest(content)
  end
end

# NOTE: this code is taken from https://github.com/rubyzip/rubyzip examples
# Usage:
#   directoryToZip = "/tmp/input"
#   outputFile = "/tmp/out.zip"
#   zf = ZipFileGenerator.new(directoryToZip, outputFile)
#   zf.write()
class ZipFileGenerator

  # Initialize with the directory to zip and the location of the output archive.
  def initialize(inputDir, outputFile)
    @inputDir = inputDir
    @outputFile = outputFile
  end

  # Zip the input directory.
  def write()
    entries = Dir.entries(@inputDir); entries.delete("."); entries.delete("..")
    io = Zip::File.open(@outputFile, Zip::File::CREATE);

    writeEntries(entries, "", io)
    io.close();
  end

  # A helper method to make the recursion work.
  private
  def writeEntries(entries, path, io)

    entries.each { |e|
      zipFilePath = path == "" ? e : File.join(path, e)
      diskFilePath = File.join(@inputDir, zipFilePath)
      # puts "Deflating " + diskFilePath
      if File.directory?(diskFilePath)
        io.mkdir(zipFilePath)
        subdir =Dir.entries(diskFilePath); subdir.delete("."); subdir.delete("..")
        writeEntries(subdir, zipFilePath, io)
      else
        io.get_output_stream(zipFilePath) { |f| f.puts(File.open(diskFilePath, "rb").read())}
      end
    }
  end
end
