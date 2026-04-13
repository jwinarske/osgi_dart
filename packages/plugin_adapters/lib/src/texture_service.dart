/// Common service property keys used by all GPU-texture plugin adapters.
///
/// All adapters register `textureId` as a service property so UI bundles
/// can reference the rendered output via Flutter's `Texture(textureId:)`.
abstract final class TextureServiceProperties {
  static const textureId = 'textureId';
  static const renderer = 'renderer';
  static const format = 'format';
  static const width = 'width';
  static const height = 'height';
}
