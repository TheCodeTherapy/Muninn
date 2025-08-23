#version 100
precision highp float;
precision highp sampler2D;

uniform sampler2D inputTexture;
uniform sampler2D lowerMipTexture;
uniform vec2 texelSize;
uniform float mipWeight;
uniform float radius;

varying vec2 fragTexCoord;

void main() {
  // 9-tap upsample with radius-scaled kernel
  vec4 color = vec4(0.0);

  // scale texel size by radius for larger/smaller blur kernel
  vec2 scaledTexelSize = texelSize * radius;

  // tent filter for smooth upsampling
  color += texture2D(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, -scaledTexelSize.y)) * 0.0625;
  color += texture2D(inputTexture, fragTexCoord + vec2(0.0, -scaledTexelSize.y)) * 0.125;
  color += texture2D(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, -scaledTexelSize.y)) * 0.0625;

  color += texture2D(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, 0.0)) * 0.125;
  color += texture2D(inputTexture, fragTexCoord) * 0.25;
  color += texture2D(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, 0.0)) * 0.125;

  color += texture2D(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, scaledTexelSize.y)) * 0.0625;
  color += texture2D(inputTexture, fragTexCoord + vec2(0.0, scaledTexelSize.y)) * 0.125;
  color += texture2D(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, scaledTexelSize.y)) * 0.0625;

  // add the lower mip level contribution
  vec4 lowerMip = texture2D(lowerMipTexture, fragTexCoord);

  gl_FragColor = color + lowerMip * mipWeight;
}
