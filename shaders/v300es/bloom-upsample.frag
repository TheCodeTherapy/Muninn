#version 300 es
precision highp float;
precision highp sampler2D;

uniform sampler2D inputTexture;
uniform sampler2D lowerMipTexture;
uniform vec2 texelSize;
uniform float mipWeight;
uniform float radius;

in vec2 fragTexCoord;
out vec4 fragColor;

void main() {
  // 9-tap upsample with radius-scaled kernel
  vec4 color = vec4(0.0);

  // scale texel size by radius for larger/smaller blur kernel
  vec2 scaledTexelSize = texelSize * radius;

  // tent filter for smooth upsampling
  color += texture(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, -scaledTexelSize.y)) * 0.0625;
  color += texture(inputTexture, fragTexCoord + vec2(0.0, -scaledTexelSize.y)) * 0.125;
  color += texture(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, -scaledTexelSize.y)) * 0.0625;

  color += texture(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, 0.0)) * 0.125;
  color += texture(inputTexture, fragTexCoord) * 0.25;
  color += texture(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, 0.0)) * 0.125;

  color += texture(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, scaledTexelSize.y)) * 0.0625;
  color += texture(inputTexture, fragTexCoord + vec2(0.0, scaledTexelSize.y)) * 0.125;
  color += texture(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, scaledTexelSize.y)) * 0.0625;

  // add the lower mip level contribution
  vec4 lowerMip = texture(lowerMipTexture, fragTexCoord);

  fragColor = color + lowerMip * mipWeight;
}
