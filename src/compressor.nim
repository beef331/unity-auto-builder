import nimarchive/archive, os, strutils

proc compress*(name : string, paths : seq[string])=
    var 
        a : ptr archive
        entry : ptr archive_entry
        info : FileInfo
        buff : array[8192,char]
        len  : int
        files : seq[string]
    a = archiveWriteNew()
    discard archiveWriteSetFormatZip(a)
    discard archiveWriteOpenFilename(a,name)

    for path in paths:
        if(dirExists(path)):
            for dir in walkDirRec(path):
                if(fileExists(dir)): files.add(dir)

    for path in files:
        let 
            file = open(path)
            name = path.split(DirSep,1)[1]
        info = getFileInfo(file)
        entry = archiveEntryNew()
        archiveEntrySetPathname(entry,name)
        archiveEntrySetSize(entry,info.size)
        archiveEntrySetFiletype(entry,AE_IFREG.cuint)
        archiveEntrySetPerm(entry,0644)
        discard archiveWriteHeader(a,entry)
        len = file.readBuffer(buff.addr,buff.len)

        while len > 0:
            discard archiveWriteData(a,buff.addr,len.uint)
            len = file.readBuffer(buff.addr,buff.len)

    discard archiveWriteClose(a)
    discard archiveWriteFree(a)