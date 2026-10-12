extends RefCounted
# Bounded render-thread command cursor. It never changes GPU acceptance or dt.
# Completion observations bound queued submissions; no readback between chunks.
var owner
var chunks=[]
var cursor=0
var costs=[]
var pending={}
var timing_records={}
var missing_timing_records=0
var seen_frame=-1
var serial=0
var last_completed=0
var maximum_queue=0
func _init(controller):
 owner=controller;chunks=owner.command_chunks()
 costs.resize(chunks.size());costs.fill(500000.0)
func consume_timestamps():
 var rd=owner.rd;var completed=rd.get_captured_timestamps_frame()
 if completed==seen_frame:return
 seen_frame=completed
 var begins={};var totals={}
 for k in rd.get_captured_timestamps_count():
  var name=rd.get_captured_timestamp_name(k)
  if not name.begins_with(owner.timestamp_prefix+"/chunk/"):continue
  var parts=name.split("/");var id=int(parts[2]);var sequence=int(parts[3]);var index=int(parts[4]);var key=str(id)+"/"+str(sequence)
  var time=rd.get_captured_timestamp_gpu_time(k)
  if parts[5]=="begin":begins[key]=time
  elif begins.has(key):
   var duration=time-begins[key];owner.total_gpu_ns+=duration
   costs[index]=lerpf(costs[index],maxf(duration,2000),.25)
   totals[id]=totals.get(id,0)+duration
 for id in totals:
  if timing_records.has(id):
   var row=timing_records[id];row.gpu_ns=totals[id];row.completed_frame=completed
   owner.telemetry.emit.call_deferred({"schedule_timing":row.duplicate(true)})
   pending.erase(id);timing_records.erase(id);last_completed=maxi(last_completed,id)
 if not totals.is_empty():
  var elapsed=owner.last_stats.get("accepted_time",0.0)
  owner.telemetry.emit.call_deferred({"record_us":owner.total_record_us,"gpu_ns":owner.total_gpu_ns,"R_fluid":owner.total_gpu_ns/1e9/elapsed if elapsed>0 else -1})
func frame(steps: float):
 var rd=owner.rd;consume_timestamps()
 var quota_done=steps<=owner.last_stats.get("accepted_steps",0) if steps>=0 else -steps<=owner.last_stats.get("accepted_time",0)
 if owner.last_stats.get("failure",0)>0:return
 if quota_done and not owner.last_stats.get("pending",false) and cursor==0:return
 # At most three unfinished render-thread submissions, each bounded by budget
 # and maximum chunk count. This is a conservative completed-GPU observation.
 if pending.size()>=owner.config.get("max_inflight_submissions",3):return
 serial+=1;var started=Time.get_ticks_usec();var first_index=cursor;var count=0;var finished=0;var starts=0;var predicted=0.0
 var record={"id":serial,"record_begin_us":started,"render_frame":Engine.get_frames_drawn(),"first_chunk":first_index,"queue_before":pending.size()}
 owner.scheduled_dispatches=0;owner.scheduled_iterations=0;owner.iteration_active=false
 var list=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,owner.pipeline);rd.compute_list_bind_uniform_set(list,owner.bindings,0)
 var budget=owner.config.get("gpu_budget_ms",14.0)*1e6
 var limit=mini(96,chunks.size()*owner.config.get("batches",4))
 while count<limit:
  if count>0 and owner.config.get("frame_budget",true) and predicted+costs[cursor]>budget:break
  var stamp=owner.timestamp_prefix+"/chunk/%d/%d/%d/"%[serial,count,cursor]
  rd.capture_timestamp(stamp+"begin")
  if cursor==0:
   starts+=1
  for command in chunks[cursor]:owner._dispatch(list,command[0],command[1],steps)
  rd.capture_timestamp(stamp+"end")
  predicted+=costs[cursor];cursor+=1;count+=1
  if cursor==chunks.size():
   cursor=0;finished+=1
   # Once the acknowledged quota is met, finish the partial cycle exactly.
   # Continuing a whole multiple of cycles preserves a nonzero cursor forever.
   if quota_done:break
  if owner.config.get("frame_budget",true) and Time.get_ticks_usec()-started>=owner.config.get("cpu_budget_ms",4.0)*1000:break
 rd.compute_list_end()
 owner.batches_last_frame=finished;var cpu=Time.get_ticks_usec()-started;owner.total_record_us+=cpu
 record.merge({"record_us":cpu,"chunks":count,"finished_batches":finished,"started_batches":starts,"scheduled_iterations":owner.scheduled_iterations,"scheduled_dispatches":owner.scheduled_dispatches,"predicted_gpu_ns":predicted,"next_chunk":cursor,"queue_depth":pending.size()+1})
 pending[serial]=record;timing_records[serial]=record
 # Viewport resize/readback can replace the engine's single exposed timestamp
 # frame. Keep queue completion independent of optional timing availability.
 for old in timing_records.keys():
  if old<serial-128:timing_records.erase(old);missing_timing_records+=1
 maximum_queue=maxi(maximum_queue,pending.size())
 var id=serial;var batch_count=finished;var issued=Time.get_ticks_usec()
 rd.buffer_get_data_async(owner.control,func(data):
  if owner==null or owner.closed:return
  # Readback latency is an overlapping diagnostic, never GPU execution time.
  for completed_id in pending.keys():
   if completed_id<=id:pending.erase(completed_id)
  owner._stats(data)
  owner.telemetry.emit.call_deferred({"record_begin_us":started,"submission_id":id,"submission_batches":batch_count,"submission_chunks":count,"submission_render_frame":record.render_frame,"submission_accepted_steps":int(data.decode_float(8)),"submission_accepted_time":data.decode_float(4),"submission_iterations":int(data.decode_float(72)),"queue_depth":pending.size(),"maximum_queue_depth":maximum_queue,"scheduled_dispatches":record.scheduled_dispatches,"scheduled_iterations":record.scheduled_iterations,"record_us_submission":cpu,"readback_latency_us":Time.get_ticks_usec()-issued,"missing_timing_records":missing_timing_records,"work_schedule":"chunks","chunk_cursor":record.next_chunk})
 )
