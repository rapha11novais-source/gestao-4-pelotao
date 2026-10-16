import {stmt,db,UserError,textValue,integer,auditStmt,type Actor} from './server.ts';
import {serviceCommander,serviceEvent} from './services.ts';
const q=(tx:any,sql:string,...args:any[])=>tx.prepare(sql).bind(...args);
export async function fixedProfiles(a:Actor,services:any[],members:any[]){
 const rows=await stmt('SELECT f.*,o.name AS officer_name,o.registration AS officer_registration,o.home_platoon FROM fixed_pistols f JOIN officers o ON o.id=f.officer_id ORDER BY f.created_at DESC').all<any>();
 return rows.results.filter(f=>a.is_global||f.officer_id===a.officer_id||a.capabilities?.officers&&f.home_platoon===a.home_platoon||services.some(s=>s.status!=='encerrado'&&serviceCommander(a,s)&&members.some(m=>m.service_id===s.id&&m.officer_id===f.officer_id&&m.status==='ativo')));
}
export async function fixedAccess(tx:any,a:Actor,officerId:string,serviceId=''){
 const o=await q(tx,'SELECT * FROM officers WHERE id=? AND active=1 AND validated=1 AND deleted_at IS NULL',officerId).first<any>();if(!o)throw new UserError('Policial ativo e validado não encontrado.',403);
 if(serviceId){const v=await q(tx,"SELECT * FROM services WHERE id=? AND status<>'encerrado' FOR UPDATE",serviceId).first<any>();const m=await q(tx,"SELECT * FROM service_members WHERE service_id=? AND officer_id=? AND status='ativo' FOR UPDATE",serviceId,officerId).first<any>();if(!v||!m)throw new UserError('Policial não integra este serviço ativo.',403);if(!a.is_global&&!a.cities?.includes(v.city)&&!a.managementCities?.includes(v.city))throw new UserError('Serviço de outro pelotão não autorizado.',403);await q(tx,"SELECT set_config('app.fixed_load_service_id',?,true)",serviceId).first();}
 if(!(await q(tx,'SELECT private.fixed_load_authorized(?,?) AS allowed',a.id,officerId).first<any>())?.allowed)throw new UserError('Somente o próprio policial, seu comandante de guarnição em serviço ou o gestor autorizado pode cadastrar esta carga fixa.',403);return o;
}
export async function saveFixedProfile(tx:any,a:Actor,officerId:string,body:any,now:string,serviceId=''){
 const o=await fixedAccess(tx,a,officerId,serviceId);await q(tx,'SELECT id FROM officers WHERE id=? FOR UPDATE',o.id).first();
 const current=await q(tx,'SELECT * FROM fixed_pistols WHERE officer_id=? AND active FOR UPDATE',o.id).first<any>();
 if(body===undefined){if(!current?.model_code||!current.ballistic_plate||current.ammunition===null)throw new UserError('Complete o Cadastro de Carga Fixa: modelo, série, munições e placa balística.');return current;}
 const model_code=textValue(body.model_code,20),serial=textValue(body.serial,100),ballistic_plate=textValue(body.ballistic_plate,100),ammunition=integer(body.ammunition,0),profile_notes=textValue(body.profile_notes),reason=textValue(body.replacement_reason);
 if(!['PT100','GLOCK','PT840'].includes(model_code)||!serial||!ballistic_plate||!/[a-zA-Z0-9]/.test(serial)||!/[a-zA-Z0-9]/.test(ballistic_plate))throw new UserError('Selecione PT100, GLOCK ou PT840 e informe a série e a identificação da placa.');if(ammunition===0&&profile_notes.length<5)throw new UserError('Descreva a quantidade zero de munições da carga fixa.');
 const manufacturer=textValue(body.manufacturer,100)||'Não informado',caliber=textValue(body.caliber,100)||'Não informado';
 if(current&&current.model_code===model_code&&current.serial===serial&&current.ballistic_plate===ballistic_plate&&current.ammunition===ammunition&&current.profile_notes===profile_notes&&current.manufacturer===manufacturer&&current.caliber===caliber)return current;
 if(current&&reason.length<5)throw new UserError('Justifique a atualização da carga fixa; o cadastro anterior será preservado.');
 if(await q(tx,"SELECT id FROM inventory WHERE deleted_at IS NULL AND quantity>0 AND ((category='armas' AND upper(regexp_replace(serial,'[^a-zA-Z0-9]','','g'))=upper(regexp_replace(?,'[^a-zA-Z0-9]','','g'))) OR (category IN('coletes','placas') AND upper(regexp_replace(serial,'[^a-zA-Z0-9]','','g'))=upper(regexp_replace(?,'[^a-zA-Z0-9]','','g')))) LIMIT 1",serial,ballistic_plate).first())throw new UserError('Pistola ou placa pertence ao acervo cadastrado do DPM. Use a cautela temporária correspondente.');
 // Serialize identification claims across officers, including concurrent requests.
 for(const key of ['pistola:'+serial.replace(/[^a-zA-Z0-9]/g,'').toUpperCase(),'placa:'+ballistic_plate.replace(/[^a-zA-Z0-9]/g,'').toUpperCase()].sort())await q(tx,'SELECT pg_advisory_xact_lock(hashtextextended(?,0))',key).first();
 if(await q(tx,"SELECT id FROM fixed_pistols WHERE active AND officer_id<>? AND (upper(regexp_replace(serial,'[^a-zA-Z0-9]','','g'))=upper(regexp_replace(?,'[^a-zA-Z0-9]','','g')) OR upper(regexp_replace(ballistic_plate,'[^a-zA-Z0-9]','','g'))=upper(regexp_replace(?,'[^a-zA-Z0-9]','','g'))) LIMIT 1",o.id,serial,ballistic_plate).first())throw new UserError('A pistola ou placa já está vinculada a outro policial.',409);
 if(await q(tx,"SELECT m.officer_id FROM service_members m JOIN services s ON s.id=m.service_id WHERE m.officer_id<>? AND m.status='ativo' AND s.status<>'encerrado' AND (upper(regexp_replace(m.fixed_load_confirmation->>'serial','[^a-zA-Z0-9]','','g'))=upper(regexp_replace(?,'[^a-zA-Z0-9]','','g')) OR upper(regexp_replace(m.fixed_load_confirmation->>'ballistic_plate','[^a-zA-Z0-9]','','g'))=upper(regexp_replace(?,'[^a-zA-Z0-9]','','g'))) LIMIT 1",o.id,serial,ballistic_plate).first())throw new UserError('Material ainda confirmado na carga fixa de outro serviço ativo.',409);
 if(current)await q(tx,'UPDATE fixed_pistols SET active=false WHERE id=?',current.id).run();const id=crypto.randomUUID();
 await q(tx,'INSERT INTO fixed_pistols(id,officer_id,manufacturer,model,caliber,serial,created_at,created_by,replacement_reason,model_code,ammunition,ballistic_plate,profile_notes,created_by_name,created_by_registration) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',id,o.id,manufacturer,model_code,caliber,serial,now,a.id,reason,model_code,ammunition,ballistic_plate,profile_notes,a.name,a.registration||'').run();const saved=await q(tx,'SELECT * FROM fixed_pistols WHERE id=?',id).first<any>();await tx.batch([auditStmt(a,current?'Carga fixa atualizada':'Carga fixa cadastrada',id,current,{...saved,city:o.city,officer_name:o.name},now)]);if(serviceId)await serviceEvent(tx,a,serviceId,'cadastro_carga_fixa',{officer_id:o.id,profile_id:id,previous_id:current?.id||null,reason},now);return saved;
}
export async function confirmFixedForService(tx:any,a:Actor,service:any,member:any,b:any,now:string){
 if(service.status==='preparacao'||!service.conference_at)throw new UserError('Finalize a conferência inicial para confirmar a carga fixa neste serviço.',409);
 if(b.confirm_fixed_load!==true)throw new UserError('Confirme os dados da carga fixa utilizada por este policial.');await fixedAccess(tx,a,member.officer_id,service.id);
 if(member.fixed_load_confirmation)return member.fixed_load_confirmation;
 const p=await saveFixedProfile(tx,a,member.officer_id,b.fixed_load,now,service.id);
 const value={service_id:service.id,officer_id:member.officer_id,profile_id:p.id,model_code:p.model_code,serial:p.serial,ammunition:p.ammunition,ballistic_plate:p.ballistic_plate,manufacturer:p.manufacturer,caliber:p.caliber,profile_notes:p.profile_notes,confirmed_at:now,confirmed_by:a.id,confirmed_by_name:a.name,confirmed_by_registration:a.registration||''};
 await q(tx,'UPDATE service_members SET fixed_load_confirmation=?::jsonb WHERE service_id=? AND officer_id=?',JSON.stringify(value),service.id,member.officer_id).run();await serviceEvent(tx,a,service.id,'carga_fixa_confirmada',value,now);await tx.batch([auditStmt(a,'Carga fixa confirmada no serviço',service.id,null,{...value,city:service.city},now)]);member.fixed_load_confirmation=value;return value;
}
export async function fixedLoadAction(a:Actor,b:any,now:string){
 if(!['save-fixed-load','confirm-fixed-load'].includes(b.action))return null;let profile:any;
 await db().transaction(async tx=>{const id=textValue(b.officerId,100)||a.officer_id;if(!id)throw new UserError('Selecione o cadastro policial.');const sid=textValue(b.serviceId,100);
 if(b.action==='save-fixed-load'){profile=await saveFixedProfile(tx,a,id,b.fixed_load,now,sid);return;}
 const v=await q(tx,"SELECT * FROM services WHERE id=? AND status<>'encerrado' FOR UPDATE",sid).first<any>(),m=await q(tx,"SELECT * FROM service_members WHERE service_id=? AND officer_id=? AND status='ativo' FOR UPDATE",sid,id).first<any>();if(!v||!m)throw new UserError('Serviço ativo não encontrado.',403);profile=await confirmFixedForService(tx,a,v,m,b,now);
 });return {ok:true,profile};
}
