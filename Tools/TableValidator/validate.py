#!/usr/bin/env python3
"""Independent test-only validator: facelet geometry + NumPy, never the Swift cubie generator."""
import hashlib
import itertools
import json
import math
import pathlib
import platform
import re
import struct
import sys
import time
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCHEMAS = [('twistMove',2187,18,2),('flipMove',2048,18,2),('sliceMove',495,18,2),
           ('cornerPermMove',40320,10,2),('edgePermMove',40320,10,2),('slicePermMove',24,10,1),
           ('twistSliceDistance',2187,495,1),('flipSliceDistance',2048,495,1),
           ('cornerSlicePermDistance',40320,24,1),('edgeSlicePermDistance',40320,24,1)]
CORNERS = np.array([[8,9,20],[6,18,38],[0,36,47],[2,45,11],[29,26,15],[27,44,24],[33,53,42],[35,17,51]])
EDGES = np.array([[5,10],[7,19],[3,37],[1,46],[32,16],[28,25],[30,43],[34,52],[23,12],[21,41],[50,39],[48,14]])
CORNER_COLORS = np.array([[0,1,2],[0,2,4],[0,4,5],[0,5,1],[3,2,1],[3,4,2],[3,5,4],[3,1,5]],dtype=np.uint8)
EDGE_COLORS = np.array([[0,1],[0,2],[0,4],[0,5],[3,1],[3,2],[3,4],[3,5],[2,1],[2,4],[5,4],[5,1]],dtype=np.uint8)
COMBINATIONS = np.array(list(itertools.combinations(range(12),4)))
SLICE_RANK = np.full(4096,-1,dtype=np.int64)
SLICE_RANK[(1 << COMBINATIONS).sum(axis=1)] = np.arange(495)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def equal(actual, expected, name):
    require(actual.shape == expected.shape, f'{name}: shape mismatch')
    difference = np.flatnonzero(actual != expected)
    require(difference.size == 0, f'{name}: mismatching entries, first {difference[:8].tolist()}')


def mutation_detected(actual, expected, limit, name):
    mutant = actual.copy()
    location = mutant.size//2
    mutant.flat[location] = (int(mutant.flat[location])+1)%limit
    try:
        equal(mutant,expected,name)
    except ValueError:
        return True
    raise ValueError(f'{name}: validator failed to detect corrupted entry')


def permutation_rank(values):
    count = values.shape[1]
    rank = np.zeros(values.shape[0],dtype=np.int64)
    for position in range(count-1):
        rank += (values[:,position+1:] < values[:,position,None]).sum(axis=1)*math.factorial(count-position-1)
    return rank


def representation(name, rows):
    cp = np.tile(np.arange(8,dtype=np.uint8),(rows,1)); co = np.zeros((rows,8),dtype=np.uint8)
    ep = np.tile(np.arange(12,dtype=np.uint8),(rows,1)); eo = np.zeros((rows,12),dtype=np.uint8)
    if name == 'twistMove':
        co[:,:7] = (np.arange(rows)[:,None] // (3**np.arange(6,-1,-1)))%3
        co[:,7] = (-co[:,:7].sum(axis=1,dtype=np.int64))%3
    elif name == 'flipMove':
        eo[:,:11] = (np.arange(rows)[:,None] // (2**np.arange(10,-1,-1)))%2
        eo[:,11] = eo[:,:11].sum(axis=1)%2
    elif name == 'sliceMove':
        for row, positions in enumerate(COMBINATIONS):
            ep[row,positions] = np.arange(8,12)
            ep[row,[p for p in range(12) if p not in positions]] = np.arange(8)
    elif name == 'cornerPermMove':
        cp = np.array(list(itertools.permutations(range(8))),dtype=np.uint8)
    elif name == 'edgePermMove':
        ep[:,:8] = np.array(list(itertools.permutations(range(8))),dtype=np.uint8)
    elif name == 'slicePermMove':
        ep[:,8:] = np.array(list(itertools.permutations(range(8,12))),dtype=np.uint8)
    faces = np.tile(np.repeat(np.arange(6,dtype=np.uint8),9),(rows,1))
    indices = np.arange(rows)
    for position in range(8):
        for sticker in range(3):
            faces[indices,CORNERS[position,(sticker+co[:,position])%3]] = CORNER_COLORS[cp[:,position],sticker]
    for position in range(12):
        for sticker in range(2):
            faces[indices,EDGES[position,(sticker+eo[:,position])%2]] = EDGE_COLORS[ep[:,position],sticker]
    return faces


def coordinate(name, faces):
    if name == 'twistMove':
        observed = faces[:,CORNERS]
        orientation = ((observed == 0)|(observed == 3)).argmax(axis=2)
        return (orientation[:,:7]*(3**np.arange(6,-1,-1))).sum(axis=1)
    if name == 'cornerPermMove':
        observed = np.sort(faces[:,CORNERS],axis=2)
        pieces = np.full(observed.shape[:2],255,dtype=np.uint8)
        for piece, colors in enumerate(np.sort(CORNER_COLORS,axis=1)):
            pieces[(observed == colors).all(axis=2)] = piece
        require(np.all(pieces < 8),'Impossible oracle corner')
        return permutation_rank(pieces)
    observed = faces[:,EDGES]
    if name == 'sliceMove':
        occupancy = ((observed != 0)&(observed != 3)).all(axis=2)
        return SLICE_RANK[(occupancy*(1<<np.arange(12))).sum(axis=1)]
    pieces = np.full(observed.shape[:2],255,dtype=np.uint8)
    orientation = np.zeros(observed.shape[:2],dtype=np.uint8)
    for piece, colors in enumerate(EDGE_COLORS):
        direct = (observed == colors).all(axis=2)
        reverse = (observed == colors[::-1]).all(axis=2)
        pieces[direct|reverse] = piece
        orientation[reverse] = 1
    require(np.all(pieces < 12),'Impossible oracle edge')
    if name == 'flipMove':
        return (orientation[:,:11]*(2**np.arange(10,-1,-1))).sum(axis=1)
    if name == 'edgePermMove':
        return permutation_rank(pieces[:,:8])
    return permutation_rank(pieces[:,8:]-8)


def expected_transitions(name,rows,columns,golden):
    original = representation(name,rows)
    expected = np.empty((rows,columns),dtype=np.uint16)
    moves = [(f,q) for f in 'URFDLB' for q in (1,2,3)] if columns == 18 else [('U',1),('U',2),('U',3),('D',1),('D',2),('D',3),('R',2),('F',2),('L',2),('B',2)]
    for column,(face,turns) in enumerate(moves):
        moved = original
        inverse = np.argsort(golden[face])
        for _ in range(turns):
            moved = moved[:,inverse]
        expected[:,column] = coordinate(name,moved)
    return expected


def recompute_distances(left,right,goal):
    right_rows = right.shape[0]
    total = left.shape[0]*right_rows
    distance = np.full(total,255,dtype=np.uint8)
    frontier = np.array([goal],dtype=np.int64)
    distance[goal] = 0
    depth = 0
    while frontier.size:
        a,b = frontier//right_rows,frontier%right_rows
        candidates = []
        for move in range(left.shape[1]):
            targets = left[a,move].astype(np.int64)*right_rows+right[b,move]
            candidates.append(targets[distance[targets] == 255])
        frontier = np.unique(np.concatenate(candidates))
        depth += 1
        require(depth < 255,'Oracle distance overflow')
        distance[frontier] = depth
    require(np.all(distance != 255),'Oracle graph has unreachable entries')
    return distance.reshape(left.shape[0],right_rows)


def validate(directory):
    started = time.perf_counter()
    manifest_path = directory/'manifest.json'
    require(manifest_path.stat().st_size <= 65536,'Oversized manifest')
    manifest = json.loads(manifest_path.read_text())
    require(manifest['formatVersion'] == 1 and manifest['generatorVersion'] == 'cubeguide-tables-v1','Unknown manifest version')
    require(re.fullmatch('[0-9a-f]{40}',manifest['sourceCommit']) is not None,'Invalid generator source commit')
    records = manifest['tables']
    require(len(records)==10,'Missing/extra manifest tables')
    require(len({r['identifier'] for r in records}) == 10,'Duplicate table identifiers')
    golden = json.loads((ROOT/'Fixtures/Mathematics/quarter-turns.json').read_text())
    tables = []; reports = []
    for identifier,(name,rows,columns,width) in enumerate(SCHEMAS,1):
        record = next(r for r in records if r['identifier']==identifier)
        expected_size = 36+rows*columns*width
        require(record['filename']==name+'.bin','Unexpected resource path')
        require((record['rows'],record['columns'],record['elementWidth'],record['byteCount']) == (rows,columns,width,expected_size),'Manifest dimensions mismatch')
        path = directory/(name+'.bin')
        require(path.stat().st_size==expected_size,'Resource file size mismatch')
        data = path.read_bytes()
        require(hashlib.sha256(data).hexdigest()==record['sha256'],'Resource hash mismatch')
        require(struct.unpack('<8sIIIIIQ',data[:36])==(b'CUBETBL1',1,identifier,rows,columns,width,rows*columns*width),'Resource header mismatch')
        actual = np.frombuffer(data[36:],dtype='<u2' if width == 2 else 'u1').reshape(rows,columns)
        if identifier <= 6:
            expected = expected_transitions(name,rows,columns,golden)
            limit = rows
        else:
            l,r,goal = [(0,2,494),(1,2,494),(3,5,0),(4,5,0)][identifier-7]
            expected = recompute_distances(tables[l],tables[r],goal)
            limit = 255
        equal(actual,expected,name)
        killed = mutation_detected(actual,expected,limit,name)
        tables.append(actual)
        report = {'table':name,'entriesCompared':int(actual.size),'maximum':int(actual.max()),'mutationDetected':killed,'result':'passed'}
        reports.append(report)
        print(json.dumps(report),flush=True)
    payload = sum(r*c*w for _,r,c,w in SCHEMAS)
    require(payload == 5815005,'Unexpected payload budget')
    return {'result':'passed','sourceCommit':manifest['sourceCommit'],'tables':reports,'payloadBytes':payload,
            'seconds':time.perf_counter()-started,'python':platform.python_version(),'numpy':np.__version__,'platform':platform.platform()}


if __name__ == '__main__':
    require(len(sys.argv)==2,'Usage: validate.py TABLE_DIRECTORY')
    report = validate(pathlib.Path(sys.argv[1]))
    print(json.dumps(report,indent=2))
