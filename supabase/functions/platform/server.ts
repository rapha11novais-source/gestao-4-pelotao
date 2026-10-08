import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
import {database} from './db.ts';
export class UserError extends Error {constructor(message:string,public status=400){super(message);}}
export const db=()=>database;
export const stmt=(query:string,...args:unknown[])=>db().prepare(query).bind(...args);
export type Actor={id:string;officer_id:string|null;role:string;email:string;name:string};
async function verifiedUser(req:Request){const token=req.headers.get('Authorization')?.match(/^Bearer (.+)$/i)?.[1];if(!token)throw new UserError('Entre com sua conta para continuar.',401);const keys=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}');const key=keys.default||Deno.env.get('SUPABASE_ANON_KEY');const url=Deno.env.get('SUPABASE_URL');if(!url||!key)throw new UserError('O serviço de autenticação está indisponível.',503);const client=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});const {data,error}=await client.auth.getUser(token);if(error||!data.user?.email||!data.user.email_confirmed_at)throw new UserError('A sessão é inválida ou o e-mail ainda não foi confirmado.',401);return data.user;}
export async function actor(req:Request):Promise<Actor>{
 const user=await verifiedUser(req);const email=user.email!.toLowerCase();const uid=user.id;const name=user.user_metadata?.full_name||email;
 let p=await stmt('SELECT * FROM principals WHERE id=?',uid).first<Actor>();
 const settings=await stmt('SELECT value FROM settings WHERE key=?','owner_email').first<{value:string}>();
 const owner=(settings?.value||'').trim().toLowerCase();
 if(!p&&owner&&email===owner){const created=await stmt("INSERT OR IGNORE INTO principals(id,officer_id,role,email,name) VALUES(?,NULL,'comando',?,?)",uid,email,name).run();if(created.meta.changes)await auditStmt({id:uid,officer_id:null,role:'comando',email,name},'Acesso inicial autorizado',uid,null,{role:'comando',militaryIdentityLinked:false}).run();p=await stmt('SELECT * FROM principals WHERE id=?',uid).first<Actor>();}
 const o=await stmt('SELECT * FROM officers WHERE auth_user_id=? OR (auth_user_id IS NULL AND lower(email)=?)',uid,email).first<any>();
 if(o){if(!o.active||!o.validated)throw new UserError('Seu cadastro precisa de autorização ou está inativo. Procure o gestor.',403);await stmt('INSERT INTO principals(id,officer_id,role,email,name) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET officer_id=excluded.officer_id,role=excluded.role,email=excluded.email,name=excluded.name',uid,o.id,o.role,email,o.name).run();return {id:uid,officer_id:o.id,role:o.role,email,name:o.name};}
 if(p?.officer_id)throw new UserError('Seu cadastro precisa de autorização ou está inativo. Procure o comando.',403);
 if(!p)throw new UserError('Seu e-mail ainda não foi autorizado pelo comando.',403);
 return p;
}
export function admin(a:Actor){if(!['comando','administrador'].includes(a.role))throw new UserError('Esta operação exige autorização administrativa.',403);}
export function manager(a:Actor){if(a.role!=='comando')throw new UserError('Somente o gestor do pelotão pode realizar esta operação.',403);}
export function authAdmin(){const keys=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}');const key=keys.default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');const url=Deno.env.get('SUPABASE_URL');if(!key||!url)throw new UserError('O serviço de contas está indisponível.',503);return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});}
export function textValue(v:unknown,max=2000){return typeof v==='string'?v.trim().slice(0,max):'';}
export function integer(v:unknown,min=0,max=1000000){if(!Number.isInteger(v)||Number(v)<min||Number(v)>max)throw new UserError('Informe uma quantidade inteira válida.');return Number(v);}
export function auditStmt(a:Actor,action:string,entity:string,before:unknown,after:unknown,now=new Date().toISOString()){return stmt('INSERT INTO audit(id,actor,actor_name,action,entity,before,after,created_at) VALUES(?,?,?,?,?,?,?,?)',crypto.randomUUID(),a.id,a.name,action,entity,before==null?null:JSON.stringify(before),after==null?null:JSON.stringify(after),now);}
export function guard(id:string,query:string,...args:unknown[]){return stmt(`INSERT INTO operation_guards(id,ok) VALUES (?,CASE WHEN (${query}) THEN 1 ELSE 0 END)`,id,...args);}
export function clearGuard(id:string){return stmt('DELETE FROM operation_guards WHERE id=?',id);}
