import {withStructure} from './structure.ts';
import {bootstrapCredentials} from './credentials.ts';
import {GET,POST} from './routes.ts';
import {setupAdministrator} from './setup.ts';
async function handleRequest(req:Request){
 const origin=req.headers.get('Origin');const allowed=[Deno.env.get('APP_ORIGIN')||'https://rapha11novais-source.github.io','https://gestao-pelotoes.github.io'];
 if(origin&&!allowed.includes(origin))return Response.json({error:'Origem da solicitação não autorizada.'},{status:403});
 const headers=new Headers({'Access-Control-Allow-Methods':'GET,POST,OPTIONS','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info,x-upload-module','Vary':'Origin','Cache-Control':'no-store'});if(origin&&allowed.includes(origin))headers.set('Access-Control-Allow-Origin',origin);
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 const response=req.method==='POST'&&new URL(req.url).searchParams.get('action')==='bootstrap-access'?await bootstrapCredentials(req):req.method==='POST'&&new URL(req.url).searchParams.get('action')==='setup'?await setupAdministrator(req):req.method==='GET'?await GET(req):req.method==='POST'?await POST(req):Response.json({error:'Método inválido.'},{status:405});
 response.headers.forEach((value,key)=>headers.set(key,value));return new Response(response.body,{status:response.status,headers});
}
export async function handler(req:Request){try{return await withStructure(()=>handleRequest(req));}catch(e){console.error(e instanceof Error?e.message:e);return Response.json({error:'O serviço está temporariamente indisponível.'},{status:503});}}
Deno.serve(handler);
