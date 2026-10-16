import {AsyncLocalStorage} from 'node:async_hooks';
const actors=new AsyncLocalStorage<{id:string}>();
import postgres from 'npm:postgres@3.4.7';
let connection:ReturnType<typeof postgres>|undefined;
function sql(){const url=Deno.env.get('SUPABASE_DB_URL');if(!url)throw Error('Database connection unavailable');return connection??=postgres(url,{prepare:false,max:1,idle_timeout:20,connect_timeout:15,connection:{search_path:'private,public'}});}
// The business queries use positional parameters. No client SQL is accepted.
export function compile(query:string){let index=0;const ignore=/^INSERT OR IGNORE INTO /i.test(query);query=query.replace(/^INSERT OR IGNORE INTO /i,'INSERT INTO ');query=query.replace(/\?/g,()=>'$'+(++index));return ignore?query+' ON CONFLICT DO NOTHING':query;}
// postgres.js serializes JSONB parameters itself. Preserve TEXT JSON strings, but
// supply native objects for explicit JSON casts to avoid encoding them twice.
export function nativeParameters(query:string,args:unknown[]){let i=0;const values=[...args];for(const match of query.matchAll(/\?/g)){if(/^\s*::\s*jsonb?\b/i.test(query.slice(match.index!+1))&&typeof values[i]==='string'){values[i]=JSON.parse(values[i] as string);}i++;}return values;}
export function nativeRows(rows:any){const jsonNames=new Set((rows.columns||[]).filter((c:any)=>[114,3802].includes(c.type)).map((c:any)=>c.name));return Array.from(rows,(row:any)=>Object.fromEntries(Object.entries(row).map(([key,value])=>{if(jsonNames.has(key)&&typeof value==='string'&&/^[\[{]/.test(value.trim())){try{return [key,JSON.parse(value)];}catch{}}return [key,value]})));}
export class Statement {
 constructor(public query:string,public args:unknown[]=[],private client?:any){ }
 bind(...args:unknown[]){return new Statement(this.query,args,this.client)}
 async execute(client:any=this.client||sql()){const id=actors.getStore()?.id;const rows=id&&client===sql()?await sql().begin(async t=>{await context(t);return t.unsafe(compile(this.query),nativeParameters(this.query,this.args))}):await client.unsafe(compile(this.query),nativeParameters(this.query,this.args));return {results:nativeRows(rows),meta:{changes:rows.count??rows.length}};}
 async first<T=Record<string,unknown>>(){const rows=await this.execute();return (rows.results[0]??null) as T|null;}
 async all<T=Record<string,unknown>>(){const rows=await this.execute();return {...rows,results:rows.results as T[]};}
 async run(){return this.execute()}
}
async function context(client:any){const id=actors.getStore()?.id;if(id)await client.unsafe("SELECT set_config('app.actor_id',$1,true)",[id]);}
async function batch(client:any,statements:Statement[]){const results=[];for(const s of statements)results.push(await s.execute(client));return results;}
export const database={asActor:<T>(id:string,callback:()=>Promise<T>)=>actors.run({id},callback),prepare:(query:string)=>new Statement(query),batch:async(statements:Statement[])=>sql().begin(async t=>{await context(t);return batch(t,statements)}),transaction:<T>(callback:(tx:{prepare:(query:string)=>Statement;batch:(statements:Statement[])=>Promise<any[]>})=>Promise<T>,options?:{readOnly?:boolean}):Promise<T>=>sql().begin(async t=>{if(options?.readOnly)await t.unsafe('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY');await context(t);return callback({prepare:query=>new Statement(query,[],t),batch:statements=>batch(t,statements)})}) as Promise<T>};
