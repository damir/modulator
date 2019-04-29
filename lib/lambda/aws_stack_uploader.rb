require 'aws-sdk-s3'
require 'digest'
require 'bundler'

module AwsStackBuilder
  module_function

  S3Client = Aws::S3::Client.new

  def upload_lambda_handler
    bucket_name = Humidifier.ref("S3Bucket").reference
    lambda_handler_key = LAMBDA_HANDLER_FILE_NAME + '.rb.zip'
    source = <<~SOURCE
      # see handler AwsApiGatewayEventHandler.call(event: event, context: context) in required file
      require 'lambda/aws_lambda_handler'
      Dir.chdir('/opt/ruby/lib/' + ENV['app_dir'])
    SOURCE

    existing_handler = S3Client.get_object(
      bucket: bucket,
      key: lambda_handler_key
    ) rescue false # not found

    existing_source = Zip::InputStream.open(existing_handler.body) do |zip_file|
      zip_file.get_next_entry
      zip_file.read
    end if existing_handler

    if existing_source != source
      puts '- uploading generic lambda handler'
      source_zip_file = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry LAMBDA_HANDLER_FILE_NAME + '.rb'
        zip.print source
      end
      S3Client.put_object(
        bucket: bucket,
        key: lambda_handler_key,
        body: source_zip_file.tap(&:rewind).read
      )
    end
  end

  def upload_gems_layer
    if !app_path.join('Gemfile').exist?
      puts '- no Gemfile detected'
      return
    end

    # calculate Gemfile checksum
    checksum_path = app_path.join('.modulator/gemfile_checksum')
    old_checksum  = (checksum_path.read rescue nil)
    new_checksum  = Digest::MD5.hexdigest(File.read(app_path.join('Gemfile.lock')))

    zip_file_name = app_dir + '_gems.zip'
    gems_path = app_path.join('.modulator/gems')
    gems_zip_path = gems_path.parent.join(zip_file_name)

    if old_checksum != new_checksum
      puts '- uploading gems layer'
      checksum_path.write(new_checksum)

      # bundle gems
      Bundler.with_clean_env do
        Dir.chdir(app_path) do
          `bundle install --path=./.modulator/gems --clean`
        end
      end
      ZipFileGenerator.new(gems_path, gems_zip_path).write

      # upload zipped file
      gem_layer = S3Client.put_object(
        bucket: bucket,
        key: zip_file_name,
        body: gems_zip_path.read
      )
      # delete zipped file
      FileUtils.remove_dir(gems_path)
      gems_zip_path.delete
    else
      puts '- using existing gems layer'
      gem_layer = S3Client.get_object(bucket: bucket, key: zip_file_name)
    end

    add_layer(
      name: app_name + 'Gems',
      description: "App gems",
      s3_key: zip_file_name,
      s3_object_version: gem_layer.version_id
    )
  end

  def upload_app_layer
    wd = Pathname.getwd
    zip_file_name = app_dir + '.zip'
    app_zip_path  = wd.join(zip_file_name)

    # calculate checksum for app folder
    checksum_path = app_path.join('.modulator/app_checksum')
    old_checksum  = (checksum_path.read rescue nil)
    new_checksum  = checksum(app_path)

    if old_checksum != new_checksum
      puts '- uploading app layer'
      checksum_path.write(new_checksum)
      ZipFileGenerator.new(app_path, app_zip_path).write
      # upload zipped file
      app_layer = S3Client.put_object(
        bucket: bucket,
        key: zip_file_name,
        body: app_zip_path.read
      )
      # delete zipped file
      app_zip_path.delete
    else
      puts '- using existing app layer'
      app_layer = S3Client.get_object(bucket: bucket, key: zip_file_name)
    end

    add_layer(
      name: app_name,
      description: "App source. MD5: #{new_checksum}",
      s3_key: zip_file_name,
      s3_object_version: app_layer.version_id
    )
  end

  # add layer
  def add_layer(name:, description:, s3_key:, s3_object_version:)
    stack.add(name + 'Layer', Humidifier::Lambda::LayerVersion.new(
        compatible_runtimes: [RUBY_VERSION],
        layer_name: name,
        description: description,
        content: {
          s3_bucket: bucket,
          s3_key: s3_key,
          s3_object_version: s3_object_version
        }
      )
    )
  end

  def checksum(dir)
    files = Dir["#{dir}/**/*"].reject{|f| File.directory?(f)}
    content = files.map{|f| File.read(f)}.join
    Digest::MD5.hexdigest(content)
  end
end
