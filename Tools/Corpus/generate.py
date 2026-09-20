#!/usr/bin/env python3
"""Deterministic test-only corpus. Direct states and geometry scrambles are independently generated."""
import argparse
import hashlib
import json
import pathlib
import platform
import random

ROOT=pathlib.Path(__file__).resolve().parents[2]
SOLVED=''.join(face*9 for face in 'URFDLB')
GOLDEN_PATH=ROOT/'Fixtures/Mathematics/quarter-turns.json'
GOLDEN=json.loads(GOLDEN_PATH.read_text())
INVERSE={}
for face,destinations in GOLDEN.items():
    if sorted(destinations)!=list(range(54)):
        raise ValueError('Invalid independent golden permutation')
    inverse=[0]*54
    for source,destination in enumerate(destinations):
        inverse[destination]=source
    INVERSE[face]=inverse
CORNERS=[[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]]
EDGES=[[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]]
CORNER_NAMES=['URF','UFL','ULB','UBR','DFR','DLF','DBL','DRB']
EDGE_NAMES=['UR','UF','UL','UB','DR','DF','DL','DB','FR','FL','BL','BR']


def turn(state,face,amount):
    for _ in range(amount):
        state=''.join(state[source] for source in INVERSE[face])
    return state


def parity(permutation):
    return sum(a>b for i,a in enumerate(permutation) for b in permutation[i+1:])%2


def direct_state(rng):
    corners=list(range(8));edges=list(range(12))
    rng.shuffle(corners);rng.shuffle(edges)
    if parity(corners)!=parity(edges):
        edges[0],edges[1]=edges[1],edges[0]
    twist=[rng.randrange(3) for _ in range(7)];twist.append(-sum(twist)%3)
    flip=[rng.randrange(2) for _ in range(11)];flip.append(sum(flip)%2)
    state=list(SOLVED)
    for position,identity in enumerate(corners):
        for sticker,color in enumerate(CORNER_NAMES[identity]):
            state[CORNERS[position][(sticker+twist[position])%3]]=color
    for position,identity in enumerate(edges):
        for sticker,color in enumerate(EDGE_NAMES[identity]):
            state[EDGES[position][(sticker+flip[position])%2]]=color
    return ''.join(state)


def records(count,seed):
    if not isinstance(count,int) or count<=0 or count>1000000 or count%8:
        raise ValueError('Count must be a positive multiple of 8, at most the one-million release corpus')
    rng=random.Random(seed)
    seen=set();index=0
    for source,quota,length in [('direct',count//2,0)]+[(f'moves{length}',count//8,length) for length in [20,40,80,200]]:
        accepted=0
        while accepted<quota:
            scramble=[]
            if length==0:
                state=direct_state(rng)
            else:
                state=SOLVED
                for _ in range(length):
                    face=rng.choice('URFDLB');amount=rng.randrange(1,4)
                    state=turn(state,face,amount)
                    scramble.append(face+{1:'',2:'2',3:"'"}[amount])
            if state in seen:
                continue
            seen.add(state)
            yield {'id':f'{source}-{accepted:06}','state':state,'source':source,'seed':seed,'index':index,'scramble':' '.join(scramble),'expectedValid':True}
            accepted+=1;index+=1


def shallow():
    ordered=[SOLVED];seen={SOLVED};frontier=[SOLVED];counts=[1]
    for _ in range(4):
        following=[]
        for state in frontier:
            for face in 'URFDLB':
                for amount in [1,2,3]:
                    candidate=turn(state,face,amount)
                    if candidate not in seen:
                        seen.add(candidate);following.append(candidate)
        counts.append(len(following));ordered.extend(following);frontier=following
    return ordered,counts


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('output',type=pathlib.Path)
    parser.add_argument('--count',type=int,default=10000)
    parser.add_argument('--seed',type=lambda value:int(value,0),default=0xC0BE2026)
    parser.add_argument('--shallow',action='store_true')
    args=parser.parse_args()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    counts=None
    if args.shallow:
        states,counts=shallow()
        rows=({'id':f'shallow-{i:06}','state':state,'source':'shallow','expectedValid':True} for i,state in enumerate(states))
    else:
        rows=records(args.count,args.seed)
    digest=hashlib.sha256();actual=0;strata={}
    with args.output.open('xb') as output:
        for row in rows:
            data=(json.dumps(row,sort_keys=True,separators=(',',':'))+'\n').encode()
            output.write(data);digest.update(data);actual+=1
            strata[row['source']]=strata.get(row['source'],0)+1
    manifest={'schemaVersion':1,'generatorVersion':'cubeguide-corpus-v1','generatorSourceSHA256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
              'geometrySHA256':hashlib.sha256(GOLDEN_PATH.read_bytes()).hexdigest(),'python':platform.python_version(),
              'count':actual,'strata':strata,'seed':None if args.shallow else args.seed,'shallowLayerCounts':counts,'sha256':digest.hexdigest()}
    args.output.with_suffix('.manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))
