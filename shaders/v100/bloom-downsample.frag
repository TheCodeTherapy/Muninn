#version 100
precision highp float;
precision highp sampler2D;

uniform sampler2D inputTexture;
uniform vec2 texelSize;
uniform float radius;

varying vec2 fragTexCoord;

void main() {
  vec4 color = vec4(0.0);

  // scale texel size by radius for larger/smaller blur kernel
  vec2 scaledTexelSize = texelSize * radius;

  // center sample (highest weight)
  color += texture2D(inputTexture, fragTexCoord) * 0.196;

  // plus pattern samples
  color += texture2D(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, 0.0)) * 0.098;
  color += texture2D(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, 0.0)) * 0.098;
  color += texture2D(inputTexture, fragTexCoord + vec2(0.0, scaledTexelSize.y)) * 0.098;
  color += texture2D(inputTexture, fragTexCoord + vec2(0.0, -scaledTexelSize.y)) * 0.098;

  // diagonal samples
  color += texture2D(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, scaledTexelSize.y)) * 0.049;
  color += texture2D(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, scaledTexelSize.y)) * 0.049;
  color += texture2D(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, -scaledTexelSize.y)) * 0.049;
  color += texture2D(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, -scaledTexelSize.y)) * 0.049;

  // outer samples for smoother falloff
  color += texture2D(inputTexture, fragTexCoord + vec2(scaledTexelSize.x * 2.0, 0.0)) * 0.024;
  color += texture2D(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x * 2.0, 0.0)) * 0.024;
  color += texture2D(inputTexture, fragTexCoord + vec2(0.0, scaledTexelSize.y * 2.0)) * 0.024;
  color += texture2D(inputTexture, fragTexCoord + vec2(0.0, -scaledTexelSize.y * 2.0)) * 0.024;

  gl_FragColor = color;
}
