import postgres from 'npm:postgres@3.4.7';
let connection:ReturnType<typeof postgres>|undefined;
function sql(){const url=Deno.env.get('SUPABASE_DB_URL');if(!url)throw Error('Database connection unavailable');return connection??=postgres(url,{prepare:false,max:1,idle_timeout:20,connect_timeout:15,connection:{search_path:'private,public'}});}
// The business queries use positional parameters. No client SQL is accepted.
export function compile(query:string){let index=0;const ignore=/^INSERT OR IGNORE INTO /i.test(query);query=query.replace(/^INSERT OR IGNORE INTO /i,'INSERT INTO ');query=query.replace(/\?/g,()=>'$'+(++index));return ignore?query+' ON CONFLICT DO NOTHING':query;}
export class Statement {
 constructor(public query:string,public args:unknown[]=[]){ }
 bind(...args:unknown[]){return new Statement(this.query,args)}
 async execute(client:any=sql()){const rows=await client.unsafe(compile(this.query),this.args);return {results:Array.from(rows),meta:{changes:rows.count??rows.length}};}
 async first<T=Record<string,unknown>>(){const rows=await this.execute();return (rows.results[0]??null) as T|null;}
 async all<T=Record<string,unknown>>(){const rows=await this.execute();return {...rows,results:rows.results as T[]};}
 async run(){return this.execute()}
}
export const database={prepare:(query:string)=>new Statement(query),batch:async(statements:Statement[])=>sql().begin(async transaction=>{const results=[];for(const s of statements)results.push(await s.execute(transaction));return results})};
