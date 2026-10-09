import {stmt,db,authAdmin,auditStmt,ownerId,textValue,UserError,type Actor} from './server.ts';
export function initialPassword(o:{name:string;registration:string}){const first=o.name.trim().split(/\s+/)[0];return first.charAt(0).toLocaleUpperCase('pt-BR')+first.slice(1).toLocaleLowerCase('pt-BR')+'.'+o.registration;}
export async function changePassword(a:Actor,b:any,now:string){
 const password=typeof b.password==='string'?b.password:'';if(password.length<12||new TextEncoder().encode(password).length>72)throw new UserError('Use uma nova senha com pelo menos 12 caracteres e até 72 bytes.');
 const o=await stmt('SELECT * FROM officers WHERE id=?',a.officer_id).first<any>();if(!o||o.auth_user_id!==a.id)throw new UserError('Para alterar a senha pessoal, entre com sua matrícula.');if(password===initialPassword(o))throw new UserError('Escolha uma senha diferente da senha inicial.');
 const {error}=await authAdmin().auth.admin.updateUserById(a.id,{password});if(error)throw new UserError('Não foi possível atualizar a senha. Tente novamente.',503);
 // Authentication state is authoritative; never store or audit the plaintext password.
 await db().batch([...(o.must_change_password?[stmt('UPDATE officers SET must_change_password=false WHERE id=?',o.id)]:[]),auditStmt(a,'Senha pessoal alterada',o.id,null,{city:o.city,temporaryPasswordReplaced:true},now)]);return {ok:true};
}
export async function bootstrapCredentials(req:Request){
 let digest='';try{
  const b=await req.json();const token=typeof b.token==='string'?b.token:'';if(!/^[a-f0-9]{64}$/.test(token))return Response.json({error:'Autorização inválida.'},{status:403});
  digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token))),x=>x.toString(16).padStart(2,'0')).join('');
  const rows=await stmt("SELECT key,value FROM settings WHERE key IN ('credentials_job_hash','credentials_job_expires')").all<any>();const settings=Object.fromEntries(rows.results.map(x=>[x.key,x.value]));if(settings.credentials_job_hash!==digest||!Number.isFinite(Number(settings.credentials_job_expires))||Number(settings.credentials_job_expires)<=Date.now())return Response.json({error:'Autorização expirada ou já utilizada.'},{status:403});
  const claimed=await stmt("UPDATE settings SET value=? WHERE key='credentials_job_hash' AND value=?",'running:'+digest,digest).run();if(claimed.meta.changes!==1)return Response.json({error:'Operação já iniciada.'},{status:403});
  const id=await ownerId();if(!id)throw Error('Gestor principal indisponível');const a:Actor={id,officer_id:null,role:'gestor_geral',email:'',name:'4º Pelotão',is_global:true};
  const people=(await stmt("SELECT * FROM officers WHERE deleted_at IS NULL AND (credentials_job_id IS NULL OR credentials_job_id<>?) ORDER BY registration",digest).all<any>()).results;
  let count=0;for(const o of people){
   if(o.auth_user_id===id)continue;const identity=o.registration+'@accounts.invalid';const existing=o.auth_user_id||(await stmt('SELECT id FROM auth.users WHERE lower(email)=?',identity).first<any>())?.id;const password=initialPassword(o);if(password.length<12||new TextEncoder().encode(password).length>72)throw Error('A senha inicial não atende aos limites');
   await db().asActor(id,async()=>{
    // Block material access before changing an existing credential, including an existing session.
    await stmt('UPDATE officers SET must_change_password=true WHERE id=?',o.id).run();let uid=existing;
    if(uid){const {error}=await authAdmin().auth.admin.updateUserById(uid,{password,email:identity,email_confirm:true});if(error)throw Error('Falha ao preparar acesso');}else{const {data,error}=await authAdmin().auth.admin.createUser({email:identity,password,email_confirm:true,user_metadata:{full_name:o.name}});if(error||!data.user)throw Error('Falha ao criar acesso');uid=data.user.id;}
    await db().batch([stmt('UPDATE officers SET auth_user_id=?,must_change_password=true,credentials_job_id=? WHERE id=?',uid,digest,o.id),auditStmt(a,'Acesso inicial por matrícula preparado',o.id,null,{city:o.city,registration:o.registration,accountId:uid,passwordChangeRequired:true},new Date().toISOString())]);
   });count++;
  }
  await stmt("UPDATE settings SET value='' WHERE key='credentials_job_hash' AND value=?",'running:'+digest).run();return Response.json({ok:true,prepared:count});
 }catch{if(digest)await stmt("UPDATE settings SET value=? WHERE key='credentials_job_hash' AND value=?",digest,'running:'+digest).run();return Response.json({error:'A preparação precisa ser retomada. As contas já processadas foram preservadas.'},{status:503});}
}
