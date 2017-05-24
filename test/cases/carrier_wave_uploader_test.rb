require 'test_helper'

class CarrierWaveUploaderTest < ActiveSupport::TestCase
  def setup
    super
    MockModel.send(:extend, CarrierWaveUploader)
    MockModel.send(:attr_accessor, :image)
    MockModel.send(:attr_accessor, :images)
    @mock_model = MockModel.new(name: 'A Mock Model')
    @uploader = Class.new(CarrierWave::Uploader::Base)
    image_path = File.join(Dir.pwd, 'test', 'images')
    @image_1 = File.join(image_path, 'test-image-1.jpg')
    @image_2 = File.join(image_path, 'test-image-2.jpeg')
    @image_3 = File.join(image_path, 'test-image-3.png')
  end

  test 'should return blank uploader when nothing' do
    MockModel.mount_uploader(:image, @uploader)
    assert @mock_model.image.blank?
  end

  test 'should return blank uploader when empty string' do
    MockModel.mount_uploader(:image, @uploader)
    @mock_model.image = ''
    @mock_model.save
    mock_model = MockModel.all.first
    assert_instance_of @uploader, mock_model.image
    assert mock_model.image.blank?
  end

  test 'should retrieve file from storage' do
    MockModel.mount_uploader(:image, @uploader)
    create_with_image(@image_1)
    mock_model = MockModel.all.first
    validate_image(mock_model, 'test-image-1.jpg')
  end

  test 'should copy a file into the cache directory' do
    MockModel.mount_uploader(:image, @uploader)
    @mock_model.image = Rack::Test::UploadedFile.new(@image_1, 'image/png')
    assert_match '/tmp/carrierwave-tests/carrierwave-cache/', @mock_model.image.current_path
  end

  test 'should set the file url on the entity' do
    MockModel.mount_uploader(:image, @uploader)
    create_with_image(@image_1)
    query = CloudDatastore.dataset.query 'MockModel'
    entity = CloudDatastore.dataset.run(query).first
    assert_equal 'test-image-1.jpg', entity['image']
  end

  test 'should retrieve files from storage' do
    MockModel.mount_uploaders(:images, @uploader)
    create_with_images(@image_1, @image_2)
    mock_model = MockModel.all.first
    validate_images(mock_model, 'test-image-1.jpg', 'test-image-2.jpeg')
  end

  test 'should set an array of file identifiers' do
    MockModel.mount_uploaders(:images, @uploader)
    create_with_images(@image_1, @image_2)
    query = CloudDatastore.dataset.query 'MockModel'
    entity = CloudDatastore.dataset.run(query).first
    assert entity['images'].is_a? Array
    assert_includes entity['images'], 'test-image-1.jpg'
    assert_includes entity['images'], 'test-image-2.jpeg'
  end

  test 'should retrieve files with multiple uploaders' do
    MockModel.mount_uploader(:image, @uploader)
    MockModel.mount_uploaders(:images, @uploader)
    @mock_model.image = Rack::Test::UploadedFile.new(@image_1, 'image/png')
    create_with_images(@image_2, @image_3)
    mock_model = MockModel.all.first
    validate_image(mock_model, 'test-image-1.jpg')
    validate_images(mock_model, 'test-image-2.jpeg', 'test-image-3.png')
  end

  test 'should update file' do
    MockModel.mount_uploader(:image, @uploader)
    create_with_image(@image_1)
    @mock_model.update(image: Rack::Test::UploadedFile.new(@image_2, 'image/png'))
    mock_model = MockModel.all.first
    validate_image(mock_model, 'test-image-2.jpeg')
  end

  test 'should update files' do
    MockModel.mount_uploaders(:images, @uploader)
    create_with_images(@image_2, @image_3)
    images = [Rack::Test::UploadedFile.new(@image_1, 'image/png')]
    @mock_model.update(images: images)
    mock_model = MockModel.all.first
    validate_images(mock_model, 'test-image-1.jpg', 'test-image-2.jpeg', 'test-image-3.png')
  end

  test 'should update file with multiple uploaders' do
    MockModel.mount_uploader(:image, @uploader)
    MockModel.mount_uploaders(:images, @uploader)
    create_with_image(@image_1)
    @mock_model.update(image: Rack::Test::UploadedFile.new(@image_2, 'image/png'))
    mock_model = MockModel.all.first
    validate_image(mock_model, 'test-image-2.jpeg')
  end

  test 'should update files with multiple uploaders' do
    MockModel.mount_uploader(:image, @uploader)
    MockModel.mount_uploaders(:images, @uploader)
    create_with_images(@image_3)
    @mock_model.update(images: [Rack::Test::UploadedFile.new(@image_1, 'image/png')])
    mock_model = MockModel.all.first
    validate_images(mock_model, 'test-image-1.jpg', 'test-image-3.png')
  end

  test 'should retain file when not changed' do
    MockModel.mount_uploader(:image, @uploader)
    create_with_image(@image_2)
    @mock_model.update(name: 'No image changes')
    mock_model = MockModel.all.first
    validate_image(mock_model, 'test-image-2.jpeg')
  end

  test 'should retain files when not changed' do
    MockModel.mount_uploaders(:images, @uploader)
    create_with_images(@image_1, @image_2, @image_3)
    @mock_model.update(name: 'No image changes')
    mock_model = MockModel.all.first
    validate_images(mock_model, 'test-image-1.jpg', 'test-image-2.jpeg', 'test-image-3.png')
  end

  test 'deleting entity should delete file' do
    MockModel.mount_uploader(:image, @uploader)
    create_with_image(@image_1)
    @mock_model.destroy
    assert_equal 0, Dir[File.join(Dir.pwd, 'tmp', 'carrierwave-tests', 'uploads', '*')].size
  end

  private

  def create_with_image(file)
    @mock_model.image = Rack::Test::UploadedFile.new(file, 'image/png')
    @mock_model.save
    @mock_model = MockModel.find(@mock_model.id)
  end

  def create_with_images(*files)
    images = files.map { |file| Rack::Test::UploadedFile.new(file, 'image/png') }
    @mock_model.images = images
    @mock_model.save
    @mock_model = MockModel.find(@mock_model.id)
  end

  def validate_image(mock_model, image_name)
    assert_instance_of @uploader, mock_model.image
    assert_equal "/uploads/#{image_name}", mock_model.image.url
  end

  def validate_images(mock_model, *image_names)
    assert mock_model.images.is_a? Array
    assert_equal image_names.size, mock_model.images.size
    urls = mock_model.images.map(&:url)
    image_names.each { |name| assert_includes urls, "/uploads/#{name}" }
  end
end
