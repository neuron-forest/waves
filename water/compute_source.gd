extends RefCounted
# Expand includes before compilation so cache keys cover all shader sources.
static func expand(path: String,stack: Array[String]=[]) -> String:
 if path in stack:
  push_error("Cyclic compute include: "+path);return "#error Cyclic compute include\n"
 if not FileAccess.file_exists(path):
  push_error("Missing compute source: "+path);return "#error Missing compute source\n"
 var next=stack.duplicate();next.append(path)
 var output=""
 for line in FileAccess.get_file_as_string(path).split("\n"):
  if line.strip_edges().begins_with("#["):continue
  if line.strip_edges().begins_with("#include"):
   var relative=line.get_slice('"',1)
   output+=expand(path.get_base_dir().path_join(relative),next)+"\n"
  else:output+=line+"\n"
 return output
static func compile(rd: RenderingDevice,path: String) -> Dictionary:
 var text=expand(path)
 var source=RDShaderSource.new();source.source_compute=text
 var spirv=rd.shader_compile_spirv_from_source(source,true)
 return {"spirv":spirv,"source_sha256":text.sha256_text()}
