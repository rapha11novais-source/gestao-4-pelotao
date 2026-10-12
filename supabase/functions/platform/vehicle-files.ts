import {stmt,db,UserError,textValue,authAdmin,auditStmt,type Actor} from './server.ts';
import {vehicleRead,vehicleDuty} from './vehicles.ts';
function detect(bytes:Uint8Array){const ascii=(start:number,length:number)=>new TextDecoder().decode(bytes.slice(start,start+length));if(bytes[0]===255&&bytes[1]===216&&bytes[2]===255)return {type:'image/jpeg',ext:'jpg'};if(bytes.slice(0,8).join(',')==='137,80,78,71,13,10,26,10')return {type:'image/png',ext:'png'};if(ascii(0,4)==='RIFF'&&ascii(8,4)==='WEBP')return {type:'image/webp',ext:'webp'};if(ascii(4,4)==='ftyp'&&/heic|heix|hevc|hevx|mif1|msf1/.test(ascii(8,24)))return {type:'image/heic',ext:'heic'};if(ascii(0,5)==='%PDF-')return {type:'application/pdf',ext:'pdf'};throw new UserError('Envie uma fotografia JPG, PNG, WEBP, HEIC ou um documento PDF válido.');}
export async function vehicleUpload(a:Actor,req:Request){
 if(Number(req.headers.get('content-length')||0)>9*1024*1024)throw new UserError('O anexo deve ter até 8 MB.',413);
 const form=await req.formData(),id=textValue(form.get('vehicleId'),100),phase=textValue(form.get('phase'),30),file=form.get('file');
 if(!(file instanceof File)||file.size===0||file.size>8388608||!['entrada','saida','geral'].includes(phase))throw new UserError('Selecione um anexo válido de até 8 MB e sua finalidade.');
 const v=await stmt('SELECT * FROM vehicle_custodies WHERE id=?',id).first<any>();if(!v)throw new UserError('Veículo não encontrado.',404);vehicleRead(a,v.city);
 const manages=!!a.is_global||!!a.capabilities?.movements&&!!a.managementCities?.includes(v.city);const duty=await vehicleDuty(a,v.city).catch(e=>{if(!manages)throw e;return null});
 const bytes=new Uint8Array(await file.arrayBuffer()),format=detect(bytes);if(phase==='entrada'&&!format.type.startsWith('image/'))throw new UserError('O registro fotográfico de entrada aceita imagens. Use Anexar no histórico para documentos.');
 const fid=crypto.randomUUID(),path=id+'/'+fid+'.'+format.ext,name=file.name.replace(/[\x00-\x1f]/g,'').slice(0,180)||'anexo.'+format.ext;
 const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),x=>x.toString(16).padStart(2,'0')).join('');const client=authAdmin().storage.from('vehicle-custody');
 const {error}=await client.upload(path,bytes,{contentType:format.type,upsert:false});if(error)throw new UserError('Não foi possível enviar o anexo. Tente novamente.',503);
 try{await db().transaction(async tx=>{
  await tx.prepare('SELECT name FROM cities WHERE name=? FOR UPDATE').bind(v.city).first();const current=await vehicleDuty(a,v.city,tx).catch(e=>{if(!manages)throw e;return null});const now=new Date().toISOString(),police=current?.officer||duty?.officer;
  const actorName=police?.name||a.name,registration=police?.registration||a.registration||'',check=current?.check.id||null;
  await tx.batch([stmt('INSERT INTO vehicle_attachments(id,vehicle_id,check_id,path,phase,original_name,content_type,bytes,sha256,actor,actor_name,actor_registration,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',fid,id,check,path,phase,name,format.type,file.size,hash,a.id,actorName,registration,now),stmt('INSERT INTO vehicle_events(id,vehicle_id,check_id,kind,actor,actor_name,actor_registration,created_at,payload) VALUES(?,?,?,?,?,?,?,?,?::jsonb)',crypto.randomUUID(),id,check,'anexo',a.id,actorName,registration,now,JSON.stringify({attachment_id:fid,name,phase,bytes:file.size,sha256:hash})),auditStmt(a,'Anexo de custódia registrado',fid,null,{city:v.city,vehicle_id:id,name,phase,bytes:file.size,sha256:hash},now)]);
 });}catch(e){await client.remove([path]);throw e;}return {ok:true,id:fid};
}
