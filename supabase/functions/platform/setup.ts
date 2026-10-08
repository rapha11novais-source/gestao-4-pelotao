import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
import {stmt} from './server.ts';
const identity='4pelotao@accounts.invalid';
export async function setupAdministrator(req:Request){
 let claimed=false,hash='';
 try{
  const body=await req.json();const token=typeof body.token==='string'?body.token:'';const password=typeof body.password==='string'?body.password:'';
  if(!/^[a-f0-9]{64}$/.test(token))return Response.json({error:'Link de configuração inválido.'},{status:403});
  hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(token))),v=>v.toString(16).padStart(2,'0')).join('');
  const settings=await stmt("SELECT key,value FROM settings WHERE key IN ('setup_hash','setup_expires')").all<{key:string;value:string}>();
  const values=Object.fromEntries(settings.results.map(r=>[r.key,r.value]));
  if(values.setup_hash!==hash||Number(values.setup_expires)<=Date.now())return Response.json({error:'O link expirou ou já foi utilizado.'},{status:403});
  if(password.length<12||password.length>128)return Response.json({error:'Use uma senha de 12 a 128 caracteres.'},{status:400});
  const secretKeys=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}');const key=secretKeys.default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');const url=Deno.env.get('SUPABASE_URL');
  if(!key||!url)return Response.json({error:'Configuração temporariamente indisponível.'},{status:503});
  const claim=await stmt("UPDATE settings SET value=? WHERE key='setup_hash' AND value=?",'claimed:'+hash,hash).run();if(claim.meta.changes!==1)return Response.json({error:'O link já está sendo utilizado.'},{status:403});claimed=true;
  const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  // Reserved, non-deliverable identity backs the username; no personal email is used.
  const {error}=await client.auth.admin.createUser({email:identity,password,email_confirm:true,user_metadata:{full_name:'4º Pelotão'}});
  if(error)throw Error('Não foi possível criar o acesso. Tente novamente ou solicite suporte.');
  await stmt("UPDATE settings SET value='' WHERE key='setup_hash' AND value=?",'claimed:'+hash).run();
  return Response.json({ok:true});
 }catch{
  if(claimed)await stmt("UPDATE settings SET value=? WHERE key='setup_hash' AND value=?",hash,'claimed:'+hash).run();
  return Response.json({error:'Não foi possível concluir a configuração do acesso.'},{status:503});
 }
}
