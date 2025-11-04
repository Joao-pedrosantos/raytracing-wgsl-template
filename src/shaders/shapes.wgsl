fn set_face_normal(r: ray, outward_normal: vec3f, record: ptr<function, hit_record>)
{
  // Determine if ray hit the front face (outside) or back face (inside)
  record.frontface = dot(r.direction, outward_normal) < 0.0;
  // Make normal always point against the ray direction
  if (record.frontface) {
    record.normal = outward_normal;
  } else {
    record.normal = -outward_normal;
  }
}

fn hit_sphere(center: vec3f, radius: f32, r: ray, record: ptr<function, hit_record>, max: f32)
{
  // Vector from ray origin to sphere center
  var oc = r.origin - center;
  
  // Quadratic equation coefficients for ray-sphere intersection
  // Ray equation: P(t) = origin + t * direction
  // Sphere equation: |P - center|² = radius²
  var a = dot(r.direction, r.direction);     // ||direction||²
  var half_b = dot(oc, r.direction);         // half of b coefficient (optimization)
  var c = dot(oc, oc) - radius * radius;    // ||oc||² - radius²
  
  // Calculate discriminant to check if ray intersects sphere
  var discriminant = half_b * half_b - a * c;

  // No intersection if discriminant is negative
  if (discriminant < 0.0)
  {
    record.hit_anything = false;
    return;
  }

  // Calculate both possible intersection points
  var sqrtd = sqrt(discriminant);
  
  // Try the closer intersection point first
  var root = (-half_b - sqrtd) / a;
  if (root < RAY_TMIN || root > max)
  {
    // If closer point is invalid, try the farther intersection point
    root = (-half_b + sqrtd) / a;
    if (root < RAY_TMIN || root > max)
    {
      // Both intersection points are outside valid t range
      record.hit_anything = false;
      return;
    }
  }

  // Record the valid intersection
  record.t = root;                                    // Parameter t where intersection occurs
  record.p = ray_at(r, root);                        // 3D point of intersection
  var outward_normal = (record.p - center) / radius;  // Unit normal vector at intersection
  set_face_normal(r, outward_normal, record);        // Set normal and frontface
  record.hit_anything = true;                        // Mark that we found a valid hit
}

fn hit_quad(r: ray, Q: vec4f, u: vec4f, v: vec4f, record: ptr<function, hit_record>, max: f32)
{
  var n = cross(u.xyz, v.xyz);
  var normal = normalize(n);
  var D = dot(normal, Q.xyz);
  var w = n / dot(n.xyz, n.xyz);

  var denom = dot(normal, r.direction);
  if (abs(denom) < 0.0001)
  {
    record.hit_anything = false;
    return;
  }

  var t = (D - dot(normal, r.origin)) / denom;
  if (t < RAY_TMIN || t > max)
  {
    record.hit_anything = false;
    return;
  }

  var intersection = ray_at(r, t);
  var planar_hitpt_vector = intersection - Q.xyz;
  var alpha = dot(w, cross(planar_hitpt_vector, v.xyz));
  var beta = dot(w, cross(u.xyz, planar_hitpt_vector));

  if (alpha < 0.0 || alpha > 1.0 || beta < 0.0 || beta > 1.0)
  {
    record.hit_anything = false;
    return;
  }

  record.t = t;
  record.p = intersection;
  set_face_normal(r, normal, record);
  record.hit_anything = true;
}

fn hit_triangle(r: ray, v0: vec3f, v1: vec3f, v2: vec3f, record: ptr<function, hit_record>, max: f32)
{
  var v1v0 = v1 - v0;
  var v2v0 = v2 - v0;
  var rov0 = r.origin - v0;

  var n = cross(v1v0, v2v0);
  var q = cross(rov0, r.direction);

  var d = 1.0 / dot(r.direction, n);

  var u = d * dot(-q, v2v0);
  var v = d * dot(q, v1v0);
  var t = d * dot(-n, rov0);

  if (u < 0.0 || u > 1.0 || v < 0.0 || (u + v) > 1.0)
  {
    record.hit_anything = false;
    return;
  }

  if (t < RAY_TMIN || t > max)
  {
    record.hit_anything = false;
    return;
  }

  record.t = t;
  record.p = ray_at(r, t);
  var outward_normal = normalize(n);
  set_face_normal(r, outward_normal, record);
  record.hit_anything = true;
}

fn hit_box(r: ray, center: vec3f, rad: vec3f, record: ptr<function, hit_record>, t_max: f32)
{
  var m = 1.0 / r.direction;
  var n = m * (r.origin - center);
  var k = abs(m) * rad;

  var t1 = -n - k;
  var t2 = -n + k;

  var tN = max(max(t1.x, t1.y), t1.z);
  var tF = min(min(t2.x, t2.y), t2.z);

  if (tN > tF || tF < 0.0)
  {
    record.hit_anything = false;
    return;
  }

  var t = tN;
  if (t < RAY_TMIN || t > t_max)
  {
    record.hit_anything = false;
    return;
  }

  record.t = t;
  record.p = ray_at(r, t);
  var outward_normal = -sign(r.direction) * step(t1.yzx, t1.xyz) * step(t1.zxy, t1.xyz);
  set_face_normal(r, outward_normal, record);
  record.hit_anything = true;

  return;
}