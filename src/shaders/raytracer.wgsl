const THREAD_COUNT = 16;
const RAY_TMIN = 0.0001;
const RAY_TMAX = 100.0;
const PI = 3.1415927f;
const FRAC_1_PI = 0.31830987f;
const FRAC_2_PI = 1.5707964f;

@group(0) @binding(0)  
  var<storage, read_write> fb : array<vec4f>;

@group(0) @binding(1)
  var<storage, read_write> rtfb : array<vec4f>;

@group(1) @binding(0)
  var<storage, read_write> uniforms : array<f32>;

@group(2) @binding(0)
  var<storage, read_write> spheresb : array<sphere>;

@group(2) @binding(1)
  var<storage, read_write> quadsb : array<quad>;

@group(2) @binding(2)
  var<storage, read_write> boxesb : array<box>;

@group(2) @binding(3)
  var<storage, read_write> trianglesb : array<triangle>;

@group(2) @binding(4)
  var<storage, read_write> meshb : array<mesh>;

struct ray {
  origin : vec3f,
  direction : vec3f,
};

struct sphere {
  transform : vec4f,
  color : vec4f,
  material : vec4f,
};

struct quad {
  Q : vec4f,
  u : vec4f,
  v : vec4f,
  color : vec4f,
  material : vec4f,
};

struct box {
  center : vec4f,
  radius : vec4f,
  rotation: vec4f,
  color : vec4f,
  material : vec4f,
};

struct triangle {
  v0 : vec4f,
  v1 : vec4f,
  v2 : vec4f,
};

struct mesh {
  transform : vec4f,
  scale : vec4f,
  rotation : vec4f,
  color : vec4f,
  material : vec4f,
  min : vec4f,
  max : vec4f,
  show_bb : f32,
  start : f32,
  end : f32,
};

struct material_behaviour {
  scatter : bool,
  direction : vec3f,
};

struct camera {
  origin : vec3f,
  lower_left_corner : vec3f,
  horizontal : vec3f,
  vertical : vec3f,
  u : vec3f,
  v : vec3f,
  w : vec3f,
  lens_radius : f32,
};

struct hit_record {
  t : f32,
  p : vec3f,
  normal : vec3f,
  object_color : vec4f,
  object_material : vec4f,
  frontface : bool,
  hit_anything : bool,
};

fn ray_at(r: ray, t: f32) -> vec3f
{
  return r.origin + t * r.direction;
}

fn get_ray(cam: camera, uv: vec2f, rng_state: ptr<function, u32>) -> ray
{
  var rd = cam.lens_radius * rng_next_vec3_in_unit_disk(rng_state);
  var offset = cam.u * rd.x + cam.v * rd.y;
  return ray(cam.origin + offset, normalize(cam.lower_left_corner + uv.x * cam.horizontal + uv.y * cam.vertical - cam.origin - offset));
}

fn get_camera(lookfrom: vec3f, lookat: vec3f, vup: vec3f, vfov: f32, aspect_ratio: f32, aperture: f32, focus_dist: f32) -> camera
{
  var camera = camera();
  camera.lens_radius = aperture / 2.0;

  var theta = degrees_to_radians(vfov);
  var h = tan(theta / 2.0);
  var w = aspect_ratio * h;

  camera.origin = lookfrom;
  camera.w = normalize(lookfrom - lookat);
  camera.u = normalize(cross(vup, camera.w));
  camera.v = cross(camera.u, camera.w);

  camera.lower_left_corner = camera.origin - w * focus_dist * camera.u - h * focus_dist * camera.v - focus_dist * camera.w;
  camera.horizontal = 2.0 * w * focus_dist * camera.u;
  camera.vertical = 2.0 * h * focus_dist * camera.v;

  return camera;
}

fn environment_color(direction: vec3f, color1: vec3f, color2: vec3f) -> vec3f
{
  var unit_direction = normalize(direction);
  var t = 0.5 * (unit_direction.y + 1.0);
  var col = (1.0 - t) * color1 + t * color2;

  var sun_direction = normalize(vec3(uniforms[13], uniforms[14], uniforms[15]));
  var sun_color = int_to_rgb(i32(uniforms[17]));
  var sun_intensity = uniforms[16];
  var sun_size = uniforms[18];

  var sun = clamp(dot(sun_direction, unit_direction), 0.0, 1.0);
  col += sun_color * max(0, (pow(sun, sun_size) * sun_intensity));

  return col;
}

fn check_ray_collision(r: ray, max: f32) -> hit_record
{
  var spheresCount = i32(uniforms[19]);
  var quadsCount = i32(uniforms[20]);
  var boxesCount = i32(uniforms[21]);
  var trianglesCount = i32(uniforms[22]);
  var meshCount = i32(uniforms[27]);

  var closest = hit_record(RAY_TMAX, vec3f(0.0), vec3f(0.0), vec4f(0.0), vec4f(0.0), false, false);
  var closest_so_far = max;

  // Test all spheres
  for (var i = 0; i < spheresCount; i = i + 1)
  {
    var sphere = spheresb[i];
    var temp_record = hit_record(RAY_TMAX, vec3f(0.0), vec3f(0.0), vec4f(0.0), vec4f(0.0), false, false);

    hit_sphere(sphere.transform.xyz, sphere.transform.w, r, &temp_record, closest_so_far);

    if (temp_record.hit_anything && temp_record.t < closest_so_far) {
      closest_so_far = temp_record.t;
      closest = temp_record;
      closest.object_color = sphere.color;
      closest.object_material = sphere.material;
    }
  }

  // Test all quads
  for (var i = 0; i < quadsCount; i = i + 1)
  {
    var quad = quadsb[i];
    var temp_record = hit_record(RAY_TMAX, vec3f(0.0), vec3f(0.0), vec4f(0.0), vec4f(0.0), false, false);

    hit_quad(r, quad.Q, quad.u, quad.v, &temp_record, closest_so_far);

    if (temp_record.hit_anything && temp_record.t < closest_so_far) {
      closest_so_far = temp_record.t;
      closest = temp_record;
      closest.object_color = quad.color;
      closest.object_material = quad.material;
    }
  }

  // Test all boxes
  for (var i = 0; i < quadsCount; i = i + 1)
  {
    var box = boxesb[i];
    var temp_record = hit_record(RAY_TMAX, vec3f(0.0), vec3f(0.0), vec4f(0.0), vec4f(0.0), false, false);

    hit_box(r, box.center.xyz, box.radius.xyz, &temp_record, closest_so_far);

    if (temp_record.hit_anything && temp_record.t < closest_so_far) {
      closest_so_far = temp_record.t;
      closest = temp_record;
      closest.object_color = box.color;
      closest.object_material = box.material;
    }
  }

  // Test all triangles
  for (var i = 0; i < trianglesCount; i = i + 1)
  {
    var triangle = trianglesb[i];
    var temp_record = hit_record(RAY_TMAX, vec3f(0.0), vec3f(0.0), vec4f(0.0), vec4f(0.0), false, false);

    hit_triangle(r, triangle.v0.xyz, triangle.v1.xyz, triangle.v2.xyz, &temp_record, closest_so_far);

    if (temp_record.hit_anything && temp_record.t < closest_so_far) {
      closest_so_far = temp_record.t;
      closest = temp_record;
    }
  }

  return closest;
}

fn lambertian(normal : vec3f, absorption: f32, random_sphere: vec3f, rng_state: ptr<function, u32>) -> material_behaviour
{
  // Scatter direction: normal + random unit vector
  var scatter_direction = normal + random_sphere;

  // Catch degenerate scatter direction (when random_sphere ≈ -normal)
  if (abs(scatter_direction.x) < 1e-8 && abs(scatter_direction.y) < 1e-8 && abs(scatter_direction.z) < 1e-8) {
    scatter_direction = normal;
  }

  return material_behaviour(true, normalize(scatter_direction));
}

fn metal(normal : vec3f, direction: vec3f, fuzz: f32, random_sphere: vec3f) -> material_behaviour
{
  // Reflect the ray direction around the normal
  var reflected = reflect(direction, normal);
  // Add some fuzziness - but keep it subtle
  var scattered = reflected + fuzz * random_sphere;
  // Check if the scattered ray is in the same hemisphere as the normal
  if (dot(scattered, normal) > 0.0) {
    return material_behaviour(true, normalize(scattered));
  } else {
    return material_behaviour(false, vec3f(0.0));
  }
}

// Schlick's approximation for Fresnel reflectance
// Calculates how much light reflects vs refracts at different angles
// Glass reflects more at grazing angles (like looking at a window from the side)
fn fresnel_schlick(cos: f32, ref_idx: f32) -> f32
{
  // R0 is the reflectance at normal incidence (looking straight at surface)
  var r0 = (1.0 - ref_idx) / (1.0 + ref_idx);
  r0 = r0 * r0;
  // Schlick's polynomial approximation: R(θ) = R0 + (1-R0)(1-cos(θ))^5
  return r0 + (1.0 - r0) * pow((1.0 - cos), 5.0);
}

// Dielectric material (glass, water, diamond, etc.)
// Handles both reflection and refraction based on physics
fn dielectric(normal : vec3f, r_direction: vec3f, refraction_index: f32, frontface: bool, fuzz: f32, rng_state: ptr<function, u32>) -> material_behaviour
{
  // Determine the refraction ratio based on whether ray is entering or exiting
  var ri: f32;
  if (frontface) {
    // Ray entering the material (air -> glass)
    ri = 1.0 / refraction_index;  // e.g., 1.0/1.5 for air->glass
  } else {
    // Ray exiting the material (glass -> air)
    ri = refraction_index;  // e.g., 1.5 for glass->air
  }

  var unit_direction = normalize(r_direction);

  // Calculate angle between ray and normal
  // cos_theta tells us how perpendicular the ray hits the surface
  var cos = min(dot(-unit_direction, normal), 1.0);
  var sin = sqrt(1.0 - cos * cos);  // Pythagorean identity

  // Check for total internal reflection
  // This happens when trying to go from dense->less dense at shallow angles
  // Example: light can't escape water at angles > critical angle
  var cannot_refract = ri * sin > 1.0;
  var direction: vec3f;

  if (cannot_refract || fresnel_schlick(cos, ri) > rng_next_float(rng_state)) {
    // Reflect: Either total internal reflection, or random Fresnel reflection
    direction = reflect(unit_direction, normal);
  } else {
    // Refract: Ray bends according to Snell's law
    direction = refract(unit_direction, normal, ri);
  }

  // IMPORTANT: For clear glass, we should NOT add any fuzziness
  // Only add fuzz for frosted glass effect
  // For now, completely ignore fuzz for dielectrics to get clear glass
  // If you want frosted glass later, use a very small value like fuzz * 0.01
  
  return material_behaviour(true, normalize(direction));
}

fn emmisive(color: vec3f, light: f32) -> material_behaviour
{
  return material_behaviour(false, vec3f(0.0));
}


fn trace(r: ray, rng_state: ptr<function, u32>) -> vec3f
{
  var maxbounces = i32(uniforms[2]);
  var light = vec3f(0.0);
  var color = vec3f(1.0);
  var r_ = r;
  
  var backgroundcolor1 = int_to_rgb(i32(uniforms[11]));
  var backgroundcolor2 = int_to_rgb(i32(uniforms[12]));
  var behaviour = material_behaviour(true, vec3f(0.0));

  for (var j = 0; j < maxbounces; j = j + 1)
  {
    var record = check_ray_collision(r_, RAY_TMAX);

    if (record.hit_anything == false){
      light += color * environment_color(r_.direction, backgroundcolor1, backgroundcolor2);
      break;
    }

    // Check if emissive (light source) - material.w > 0
    if (record.object_material.w > 0.0) {
      // Emissive (light source)
      var emission_strength = record.object_material.w;
      light += color * record.object_color.xyz * emission_strength;
      break;
    }
    
    if (record.object_material.x < 0.0) {
      // Dielectric (glass, water, etc.) - negative material.x value
      var refraction_index = abs(record.object_material.x); // Use the absolute value as the refraction index
      if (refraction_index < 1.1) {
        refraction_index = 1.5; // Default to glass if not specified
      }
      
      // For clear glass, pass 0.0 as fuzz or a very small value
      // Only use material.z for frosted glass effects
      var glass_fuzz = 0.0; // For perfectly clear glass
      // Uncomment the line below if you want slight frosting based on material.z
      // var glass_fuzz = record.object_material.z * 0.01; 
      
      behaviour = dielectric(record.normal, r_.direction, refraction_index, record.frontface, glass_fuzz, rng_state);

      if (behaviour.scatter) {
        // Glass should be mostly clear - don't tint the light passing through
        // For colored glass, you can add a small tint
        // color *= record.object_color.xyz; // For colored glass
        // For clear glass, don't modify the color at all
        r_ = ray(record.p, behaviour.direction);
      } else {
        break;
      }

    } else if (record.object_material.x > 0.0) {
      // Metal - positive material.x value
      var fuzz = record.object_material.z;
      
      // Clamp fuzz to reasonable values for realistic metals
      // Most metals should have fuzz between 0.0 (mirror) and 0.3 (brushed metal)
      fuzz = clamp(fuzz, 0.0, 0.5);

      // Calculate metal reflection
      var metal_behaviour = metal(record.normal, r_.direction, fuzz, rng_next_vec3_in_unit_sphere(rng_state));

      if (metal_behaviour.scatter) {
        // IMPORTANT: Metals should use their own color, not blend with white
        // Pure metals reflect with their own color
        color *= record.object_color.xyz;
        r_ = ray(record.p, metal_behaviour.direction);
      } else {
        break;
      }

    } else {
      // Lambertian (diffuse) - material.x == 0.0
      behaviour = lambertian(record.normal, record.object_material.y, rng_next_vec3_in_unit_sphere(rng_state), rng_state);

      if (behaviour.scatter) {
        color *= record.object_color.xyz;
        r_ = ray(record.p, behaviour.direction);
      } else {
        break;
      }
    }
  }

  return light;
}

@compute @workgroup_size(THREAD_COUNT, THREAD_COUNT, 1)
fn render(@builtin(global_invocation_id) id : vec3u)
{
  var rez = uniforms[1];
  var time = u32(uniforms[0]);

  // init_rng (random number generator) we pass the pixel position, resolution and frame
  var rng_state = init_rng(vec2(id.x, id.y), vec2(u32(rez)), time);

  // Get uv
  var fragCoord = vec2f(f32(id.x), f32(id.y));
  var uv = (fragCoord + sample_square(&rng_state)) / vec2(rez);

  // Camera
  var lookfrom = vec3(uniforms[7], uniforms[8], uniforms[9]);
  var lookat = vec3(uniforms[23], uniforms[24], uniforms[25]);

  // Get camera
  var cam = get_camera(lookfrom, lookat, vec3(0.0, 1.0, 0.0), uniforms[10], 1.0, uniforms[6], uniforms[5]);
  var samples_per_pixel = i32(uniforms[4]);

  var color = vec3(0.0); // Initialize to black, not random

  // Steps:
  // 1. Loop for each sample per pixel
  // 2. Get ray
  // 3. Call trace function
  // 4. Average the color

  for (var s = 0; s < samples_per_pixel; s = s + 1)
  {
    var r = get_ray(cam, uv, &rng_state);
    var tracer = trace(r, &rng_state);
    color += tracer; // Accumulate, don't use mean function
  }

  color /= f32(samples_per_pixel); // Average by dividing by sample count

  var color_out = vec4(linear_to_gamma(color), 1.0);
  var map_fb = mapfb(id.xy, rez);
  
  // Handle accumulation
  var should_accumulate = uniforms[3];
  if (should_accumulate > 0.0) {
    var prev_color = rtfb[map_fb];
    color_out = mix(prev_color, color_out, 1.0 / (f32(time) + 1.0));
  }

  // Set the color to the framebuffer
  rtfb[map_fb] = color_out;
  fb[map_fb] = color_out;
}