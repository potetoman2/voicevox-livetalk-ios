// Records only a changed implementation that passes the complete JS regression suite.
const fs=require('node:fs'),cp=require('node:child_process'),path=require('node:path');
process.chdir(path.resolve(__dirname,'..'));
const [round,title,problem]=process.argv.slice(2),file='docs/improvement-cycles.json';
const records=fs.existsSync(file)?JSON.parse(fs.readFileSync(file,'utf8')):[];
if(Number(round)!==records.length+1)throw Error('Cycle sequence must be consecutive');
const git=args=>cp.execFileSync('git',args,{encoding:'utf8'}).trim();
const changed=git(['status','--porcelain']);
if(!/(shared\/|ios\/|native\/|scripts\/|tests\/|README|THIRD_PARTY|\.github\/)/.test(changed))throw Error('No reviewable improvement');
const run=cp.spawnSync(process.execPath,['--test','--test-reporter=tap','tests/*.test.cjs'],{encoding:'utf8'});
if(run.status!==0){process.stdout.write(run.stdout);process.stderr.write(run.stderr);}
if(run.status!==0)process.exit(run.status||1);
fs.mkdirSync('docs',{recursive:true});fs.mkdirSync('docs/validation',{recursive:true});
fs.writeFileSync(`docs/validation/cycle-${String(round).padStart(2,'0')}.txt`,run.stdout);
records.push({round:Number(round),date:'2026-10-06',title,problem,parent:git(['rev-parse','HEAD']),changed:changed.split('\n'),validation:'node --test tests/*.test.cjs',passed:Number(run.stdout.match(/# pass (\d+)/)?.[1]),failed:0,scope:'Automated regression; no claim of iPhone runtime verification'});
fs.writeFileSync(file,JSON.stringify(records,null,2)+'\n');git(['add','.']);git(['commit','-m',`Cycle ${round}: ${title}`]);
console.log(`Recorded improvement ${round}: ${title}`);
