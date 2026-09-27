// Based on:
// https://www.shadertoy.com/view/MsVXWW
shader_type spatial;
render_mode blend_mix, diffuse_burley, specular_schlick_ggx, unshaded;

uniform vec4 albedo : source_color = vec4(1.0, 0.5, 0.3, 1.0);

const float nudge = 0.739513;   // size of perpendicular vector
const float normalizer = 1.0 / sqrt(1.0 + nudge*nudge);   // pythagorean theorem on that perpendicular to maintain scale

varying vec3 global_pos;

float SpiralNoiseC(vec3 p) {
    float n = 0.0; //sin(TIME);  // noise amount
    float iter = 1.0;
    for (int i = 0; i < 8; i++) { // add sin and cos scaled inverse with the frequency
        n += -abs(sin(p.y*iter) + cos(p.x*iter)) / iter;    // abs for a ridged look
        p.xy += vec2(p.y, -p.x) * nudge; // rotate by adding perpendicular and scaling down
        p.xy *= normalizer;
        p.xz += vec2(p.z, -p.x) * nudge; // rotate on other axis
        p.xz *= normalizer;
        iter *= 1.733733; // increase the frequency
    }
    return n;
}

float NebulaNoise(vec3 p) {
    float final = p.y + 4.5;
    final -= SpiralNoiseC(p.xyz);   // mid-range noise
    final += SpiralNoiseC(p.zxy*0.5123+100.0)*4.0;   // large scale features
    return final;
}

float myMap(vec3 p) {
    float NebNoise = abs(NebulaNoise(p/0.5) * 0.5) + 0.03;
    return NebNoise;
}

void vertex() {
    global_pos = NODE_POSITION_WORLD;
}

void fragment() {
    // Получаем позицию в мировых координатах
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 ray_dir = normalize(world_pos - CAMERA_POSITION_WORLD);
    
    vec4 sum = vec4(0.0);
    // d:distance function, t:lengh of the ray
    float d=1.0, t=0.0;
    // local/tital density + weighting factor
    float ld=0.0, td=0.0, w=0.0;
    float min_dist=0.0, max_dist=100.0;
    
    ALPHA = 0.0;

    t = min_dist * step(t, min_dist);
    
    for (int i=0; i<30; i++){
        vec3 pos = world_pos + t * ray_dir;
        // break conditions
        if(td>0.9 || d<0.1*t || t>10.0 || sum.a > 0.99 || t>max_dist) break;
        
        float d = myMap(pos);
        d = max(d, 0.08); 
        
        // STAR in CENTER
        vec3 ldst = global_pos - pos; 
        float lDist = max(length(ldst), 0.001); 
        sum.rgb += (albedo.rgb/(lDist*lDist) / 30.0); //STAR and BLOOM
        
        td += 1.0/70.0;
        d = max(d, 0.04); 
        t += max(d * 0.1 * max(min(length(ldst), length(world_pos)), 1.0), 0.02); 
    }
    ALBEDO = sum.rgb; 
    ALBEDO *= t;
    ALPHA = ALBEDO.r; 
}