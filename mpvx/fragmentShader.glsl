#version 150

uniform sampler2D tex;

in vec2 fragTexCoord;

out vec4 color;

void main() {
  color = texture(tex, fragTexCoord);
//  color = vec4(0.0, 1.0, 0.0, 1.0);
}
