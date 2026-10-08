import {useId,useRef,useState,useEffect} from 'react';
import {ChevronDown,X} from 'lucide-react';
import type {Officer} from '@/lib/domain';
const normalize=(s:string)=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
export default function OfficerPicker({officers,selected,onChange,lockedId}:{officers:Officer[];selected:string[];onChange:(ids:string[])=>void;lockedId?:string|null}){
 const id=useId(),input=useRef<HTMLInputElement>(null),container=useRef<HTMLDivElement>(null);
 const [query,setQuery]=useState(''),[open,setOpen]=useState(false),[index,setIndex]=useState(0);
 const choices=officers.filter(o=>!o.deleted_at&&o.active&&(normalize(o.name).startsWith(normalize(query))||o.registration.startsWith(query.trim()))).sort((a,b)=>a.name.localeCompare(b.name,'pt-BR'));
 useEffect(()=>{if(open)document.getElementById(id+'-'+index)?.scrollIntoView({block:'nearest'});},[open,index,id]);
 function choose(o:Officer){if(!o.validated)return;if(o.id!==lockedId)onChange(selected.includes(o.id)?selected.filter(x=>x!==o.id):[...selected,o.id]);setQuery('');setIndex(0);input.current?.focus();}
 return <div className="officer-picker" ref={container} onBlur={()=>setTimeout(()=>{if(!container.current?.contains(document.activeElement))setOpen(false)},0)}>
  <div className="picker-input"><input ref={input} role="combobox" aria-label="Selecionar policiais da guarnição" aria-expanded={open} aria-autocomplete="list" aria-controls={id} aria-activedescendant={open&&choices[index]?id+'-'+index:undefined} placeholder="Digite a primeira letra do nome ou abra a lista…" value={query} onFocus={()=>setOpen(true)} onChange={e=>{setQuery(e.target.value);setOpen(true);setIndex(0)}} onKeyDown={e=>{if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();if(!open){setOpen(true);setIndex(0)}else setIndex(i=>Math.max(0,Math.min(choices.length-1,i+(e.key==='ArrowDown'?1:-1))))}else if(e.key==='Enter'&&open){e.preventDefault();if(choices[index])choose(choices[index])}else if(e.key==='Escape'){setOpen(false)}}}/><button type="button" aria-label="Mostrar todos os policiais" onClick={()=>{setQuery('');setIndex(0);setOpen(true);input.current?.focus()}}><ChevronDown size={19}/></button></div>
  {open&&<div role="listbox" id={id} aria-label="Policiais" aria-multiselectable className="picker-options">{choices.map((o,i)=><button type="button" role="option" aria-selected={selected.includes(o.id)} aria-disabled={!o.validated} id={id+'-'+i} key={o.id} className={i===index?'focused':''} onMouseEnter={()=>setIndex(i)} onMouseDown={e=>e.preventDefault()} onClick={()=>choose(o)}><strong>{o.name}</strong><small>Matrícula {o.registration} · {o.city}{!o.validated?' · Pendente de validação':''}{selected.includes(o.id)?' · Selecionado':''}</small></button>)}{!choices.length&&<p>Nenhum nome começa com esta pesquisa.</p>}</div>}
  <div className="picker-selected">{selected.map(officerId=>{const o=officers.find(x=>x.id===officerId);return o&&<span key={o.id}>{o.name}{o.id!==lockedId&&<button type="button" aria-label={'Remover '+o.name} onClick={()=>onChange(selected.filter(x=>x!==o.id))}><X size={14}/></button>}</span>})}</div>
 </div>;
}
