require 'aws-sdk-s3'
require 'digest'
require 'bundler'

module AwsStackBuilder
  module_function

  S3Client = Aws::S3::Client.new

  # bundle gems and upload all for single lambda app
  def upload_lambda_files
    puts '- bundling dependencies'
    Bundler.with_clean_env do
      Dir.chdir(app_path) do
        `bundle install`
        `bundle install --deployment --without development`
      end
    end
    FileUtils.remove_dir(app_path.join("vendor/bundle/ruby/#{GEM_PATH_RUBY_VERSION}/cache")) # remove cache dir
    upload_app_layer(sub_dirs: '', add_layer_to_stack: false) # reuse layer upload
    FileUtils.remove_dir(app_path.join('.bundle'))
    FileUtils.remove_dir(app_path.join('vendor'))
  end

  # generic handler for all lambda
  def upload_generic_lambda_handler
    lambda_handler_key = LAMBDA_HANDLER_FILE_NAME + '.rb.zip'
    source = <<~SOURCE
      require 'modulator/lambda/aws_lambda_handler'
      Dir.chdir('/opt/ruby/lib')
    SOURCE

    existing_handler = S3Client.get_object(
      bucket: s3_bucket,
      key: lambda_handler_key
    ) rescue false # not found

    if existing_handler
      existing_source = Zip::InputStream.open(existing_handler.body) do |zip_file|
        zip_file.get_next_entry
        zip_file.read
      end
      self.lambda_handler_s3_object_version = existing_handler.version_id
    end

    if existing_source != source
      puts '- uploading generic lambda handler'
      source_zip_file = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry LAMBDA_HANDLER_FILE_NAME + '.rb'
        zip.print source
      end
      new_handler = S3Client.put_object(
        bucket: s3_bucket,
        key: lambda_handler_key,
        body: source_zip_file.tap(&:rewind).read
      )
      self.lambda_handler_s3_object_version = new_handler.version_id
    end
  end

  def upload_gems_layer
    if !app_path.join('Gemfile').exist?
      puts '- no Gemfile detected'
      return
    end

    # calculate Gemfile checksum
    checksum_path = app_path.join(hidden_dir, 'gemfile_checksum')
    old_checksum  = (checksum_path.read rescue nil)
    new_checksum  = Digest::MD5.hexdigest(File.read(app_path.join('Gemfile.lock')))

    zip_file_name = app_dir + '_gems.zip'
    gems_path     = app_path.join(hidden_dir, 'gems')
    gems_zip_path = app_path.join(hidden_dir, zip_file_name)

    if old_checksum != new_checksum
      puts '- uploading gems layer'
      checksum_path.write(new_checksum)

      # bundle gems
      Bundler.with_clean_env do
        Dir.chdir(app_path) do
          `bundle install --path=./#{hidden_dir}/gems --clean`
        end
      end
      ZipFileGenerator.new(gems_path, gems_zip_path).write

      # upload zipped file
      gem_layer = S3Client.put_object(
        bucket: s3_bucket,
        key: zip_file_name,
        body: gems_zip_path.read
      )
      # delete zipped file
      FileUtils.remove_dir(gems_path)
      gems_zip_path.delete
    else
      puts '- using existing gems layer'
      gem_layer = S3Client.get_object(bucket: s3_bucket, key: zip_file_name)
    end

    add_layer(
      name: app_name + 'Gems',
      description: "App gems",
      s3_key: zip_file_name,
      s3_object_version: gem_layer.version_id
    )
  end

  def upload_app_layer(sub_dirs: 'ruby/lib', add_layer_to_stack: true)
    zip_file_name = app_dir + '.zip'
    app_zip_path  = app_path.join(hidden_dir, zip_file_name)

    # copy app code to ruby/lib in outside temp dir
    temp_dir_name = '.modulator_temp'
    temp_sub_dirs = sub_dirs
    temp_path     = app_path.parent.join(temp_dir_name)
    temp_path.join(temp_sub_dirs).mkpath
    FileUtils.copy_entry app_path, temp_path.join(temp_sub_dirs)

    # calculate checksum for app folder
    checksum_path = app_path.join(hidden_dir, 'app_checksum')
    old_checksum  = (checksum_path.read rescue nil)
    new_checksum  = Utils.checksum(app_path)

    if old_checksum != new_checksum
      puts '- uploading app layer'
      checksum_path.write(new_checksum)
      ZipFileGenerator.new(temp_path, app_zip_path).write
      # upload zipped file
      app_layer = S3Client.put_object(
        bucket: s3_bucket,
        key: zip_file_name,
        body: app_zip_path.read
      )
      # delete zipped file
      app_zip_path.delete
    else
      puts '- using existing app layer'
      app_layer = S3Client.get_object(bucket: s3_bucket, key: zip_file_name)
    end

    # delete temp dir
    FileUtils.remove_dir(temp_path)

    if add_layer_to_stack
      add_layer(
        name: app_name,
        description: "App source. MD5: #{new_checksum}",
        s3_key: zip_file_name,
        s3_object_version: app_layer.version_id
      )
    else # for single lambda app
      self.lambda_handler_s3_key = zip_file_name
      self.lambda_handler_s3_object_version = app_layer.version_id
    end
  end

  # add layer
  def add_layer(name:, description:, s3_key:, s3_object_version:)
    stack.add(name + 'Layer', Humidifier::Lambda::LayerVersion.new(
        compatible_runtimes: [RUBY_VERSION],
        layer_name: name,
        description: description,
        content: {
          s3_bucket: s3_bucket,
          s3_key: s3_key,
          s3_object_version: s3_object_version
        }
      )
    )
  end
end
