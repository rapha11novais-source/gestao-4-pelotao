import {AsyncLocalStorage} from 'node:async_hooks';
const actors=new AsyncLocalStorage<{id:string}>();
import postgres from 'npm:postgres@3.4.7';
let connection:ReturnType<typeof postgres>|undefined;
function sql(){const url=Deno.env.get('SUPABASE_DB_URL');if(!url)throw Error('Database connection unavailable');return connection??=postgres(url,{prepare:false,max:1,idle_timeout:20,connect_timeout:15,connection:{search_path:'private,public'}});}
// The business queries use positional parameters. No client SQL is accepted.
export function compile(query:string){let index=0;const ignore=/^INSERT OR IGNORE INTO /i.test(query);query=query.replace(/^INSERT OR IGNORE INTO /i,'INSERT INTO ');query=query.replace(/\?/g,()=>'$'+(++index));return ignore?query+' ON CONFLICT DO NOTHING':query;}
export class Statement {
 constructor(public query:string,public args:unknown[]=[],private client?:any){ }
 bind(...args:unknown[]){return new Statement(this.query,args,this.client)}
 async execute(client:any=this.client||sql()){const id=actors.getStore()?.id;const rows=id&&client===sql()?await sql().begin(async t=>{await context(t);return t.unsafe(compile(this.query),this.args)}):await client.unsafe(compile(this.query),this.args);return {results:Array.from(rows),meta:{changes:rows.count??rows.length}};}
 async first<T=Record<string,unknown>>(){const rows=await this.execute();return (rows.results[0]??null) as T|null;}
 async all<T=Record<string,unknown>>(){const rows=await this.execute();return {...rows,results:rows.results as T[]};}
 async run(){return this.execute()}
}
async function context(client:any){const id=actors.getStore()?.id;if(id)await client.unsafe("SELECT set_config('app.actor_id',$1,true)",[id]);}
async function batch(client:any,statements:Statement[]){const results=[];for(const s of statements)results.push(await s.execute(client));return results;}
export const database={asActor:<T>(id:string,callback:()=>Promise<T>)=>actors.run({id},callback),prepare:(query:string)=>new Statement(query),batch:async(statements:Statement[])=>sql().begin(async t=>{await context(t);return batch(t,statements)}),transaction:<T>(callback:(tx:{prepare:(query:string)=>Statement;batch:(statements:Statement[])=>Promise<any[]>})=>Promise<T>):Promise<T>=>sql().begin(async t=>{await context(t);return callback({prepare:query=>new Statement(query,[],t),batch:statements=>batch(t,statements)})}) as Promise<T>};
