#version 300 es

in vec3 vertexPosition;
in vec2 vertexTexCoord;
// in vec3 vertexNormal;
// in vec4 vertexColor;

uniform mat4 mvp;

out vec2 fragTexCoord;
// out vec4 fragVertexColor;

void main()
{
    fragTexCoord = vertexTexCoord;
    // fragVertexColor = vertexColor;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
