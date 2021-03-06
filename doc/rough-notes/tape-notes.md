# Tape notes

Rough working notes, to be sorted/rearranged later.

## Software

Additional software for working with tape devices:

    sudo apt install lsscsi

Software for translating Microsoft NTBackup stream (MTF) to TAR:

<https://sourceforge.net/projects/slackbuildsdirectlinks/files/mtftar/mtftar.tar.gz>

Download above TAR, extract to directory, go to directory and then build using:

    make

## General tape commands

List installed SCSI tape devices:

    lsscsi

Result:

    [0:0:2:0]    tape    HP       C1533A           A708  /dev/st0 
    [1:0:0:0]    disk    ATA      WDC WD2500AAKX-6 1H18  /dev/sda 
    [3:0:0:0]    cd/dvd  hp       DVD A  DH16ABSH  YHDD  /dev/sr0 
    [7:0:0:0]    disk    WD       Elements 25A2    1021  /dev/sdb

So our tape device is `/dev/st0`. For reading however we will use the " non-rewind" tape device which is `/dev/nst0`. The difference betweeen these devices:

- When using `/dev/st0`, the tape is automatically rewound after each read/write operation (e.g. using *dd*).
- When using `/dev/nst0`, the tape is left at its current position after each read/write operation.

The [*mt*](https://linux.die.net/man/1/mt) command is used for all tape operations. It must be run as root (so use *sudo*).
 
Display tape status:

    sudo mt -f /dev/st0 status

Result:

    drive type = 114
    drive status = 318767104
    sense key error = 0
    residue count = 0
    file number = 0
    block number = 0

Rewind tape:

    sudo mt -f /dev/st0 rewind

Eject tape:

    sudo mt -f /dev/st0 eject

## Note on dd usage

From [forensicswiki](https://www.forensicswiki.org/wiki/Dd):

> Having a bigger blocksize is more efficient, but if you use a 1MB block as an example and have a read error in the first sector, then dd will null fill the entire MB. Thus you should use as small a blocksize as feasible.
>
> But with linux if you go below 4KB blocksize, you can hit really bad performance issues. It can be as much as 10x slower to use the default 512 byte block as it is to use a 4KB block.
>
> Without noerror and sync, you basically don't have a forensic image. For forensic images they are mandatory.

> dd by itself does not hash, that is why the alternate command is provided. 

See also tape-specific comments in *Cautions* section!

## Make test tape

<strike>Do a short erase:

    sudo mt -f /dev/st0 erase 1 
</strike>

**NOTE** don 't do an erase (not even a short one) because it takes forever and the only way to stop it is a full system reboot!

Write two sessions:

    sudo tar -cvf /dev/nst0 /home/bcadmin/jpylyzer-test-files
    sudo tar -cvf /dev/nst0 /home/bcadmin/forensicImagingResources
    sudo tar -cvf /dev/nst0 /media/bcadmin/Elements/testBitCurator/testfloppy

Extract:

    sudo dd if=/dev/nst0 of=session1conv.dd bs=16384 conv=noerror,sync

Result: 46.5 MB file. When unpacking as tar the archives are incomplete and/or not readable!

Second attempt, omitting the *conv* swich:

    sudo dd if=/dev/nst0 of=session1conv.dd bs=16384

Result: 29.1 MB file. Unpacking as tar works!

From the [dd documentation](http://pubs.opengroup.org/onlinepubs/9699919799/utilities/dd.html):

> sync
>    Pad every input block to the size of the ibs= buffer, appending null bytes. (If either block or unblock is also specified, append <space> characters, rather than null bytes.)

A comparison of the 2 extracted files in a hex editor shows a block of around 6000 null bytes are inserted around offset 10240, adding about 6000 bytes. So let' s try the extraction with a block sixe of 10240 bytes:

    sudo dd if=/dev/nst0 of=session1convbs10240.dd bs=10240 conv=noerror,sync

Result: produces valid TAR archive of 29.1 MB. From the [tar docs](https://www.gnu.org/software/tar/manual/html_node/Blocking.html):

> In a standard tar file (no options), the block size is 512 and the record size is 10240, for a blocking factor of 20.

Solution: estimate block size by successively adding 512 bytes to start value.

TODO:

- What if the actual block size is SMALLER than 4096 bytes (current start value)? Would assume that this would result in addition of padding bytes.

- What if the block sizes varie across tape sessions?

Try with ddrescue:

    sudo ddrescue -b 10240 -v /dev/nst0 session1.dd session1.log

## Block / record size tests

Write with 1024 byte record size:

    sudo tar -cvf /dev/nst0 -b2 /media/bcadmin/Elements/testBitCurator/testfloppy

Write with 4096 byte record size:

    sudo tar -cvf /dev/nst0 -b8 /media/bcadmin/Elements/testBitCurator/testfloppy

Write with 8192 byte record size:

    sudo tar -cvf /dev/nst0 -b16 /media/bcadmin/Elements/testBitCurator/testfloppy

## Procedure for reading an NTBackup tape

1. Load the tape

2. Determine the block size by entering:

        sudo dd if=/dev/st0 of=tmp.dd ibs=128 count=1

    If this results in a *Cannot allocate memory* error message, repeat the above command with a larger ibs value (e.g. 256). Repeat until the error goes away and some data is read. For instance:

        sudo dd if=/dev/st0 of=tmp.dd ibs=512 count=1

    Results in:

        1+0 records in
        1+0 records out
        512 bytes copied, 0.308845 s, 1.7 kB/s

    Which means that the block size is 512 bytes.

    An alternative method is described [here](https://www.linuxquestions.org/questions/linux-general-1/reading-%27unknown%27-data-from-a-tape-4175500596/#post5147408):

    > Easiest way to find the actual block size for a given file on the tape is to run
    >
    >   `dd if=/dev/nst0 of=/dev/null bs=64k count=1`
    >
    > and look at the number of bytes dd reports for that single block.
    >
    > Most basic way to compare:
    >
    >
    >   `cmp <(dd if=/dev/nst0 bs=32k) <(dd if=/dev/nst1 bs=32k) && echo OK`
    >
    > Adjust the block size as you wish, of course, as long as it is large enough.

3. Read blocks (note that we're using the non-rewinding tape device ` /dev/nst0` here):

        for f in `seq 1 10`; do sudo dd if=/dev/nst0 of=tapeblock`printf "%06g" $f`.bin ibs=512; done

    Output:

        2251822+0 records in
        2251822+0 records out
        1152932864 bytes (1.2 GB, 1.1 GiB) copied, 5253.08 s, 219 kB/s
        1667+0 records in
        1667+0 records out
        853504 bytes (854 kB, 834 KiB) copied, 3.23535 s, 264 kB/s
        0+0 records in
        0+0 records out
        0 bytes copied, 0.0167298 s, 0.0 kB/s
        dd: error reading '/dev/nst0': Input/output error
        0+0 records in
        0+0 records out
        0 bytes copied, 0.00017777 s, 0.0 kB/s

    Question: why 10 iterations? What does each iteration represent (a backup session? something else?)

4. Rewind the tape:

        sudo mt -f /dev/st0 rewind

5. Eject the tape:

        sudo mt -f /dev/st0 eject

## Processing the extracted files

1. Join extracted files together using something like this:

        cat tapeblock000001.bin tapeblock000002.bin > tape.bin

## Cleaning cartridges

- [HP Cleaning Cartridge DDS for use with SureStore and all other DDS drives](https://www.bol.com/nl/p/hp-cleaning-cartridge-dds-for-use-with-surestore-and-all-other-dds-drives/9200000008139219/)

- [Fujifilm DDS Cleaning Tape](https://www.fujifilm.eu/nl/producten/opnamemedia/data-storage-media/p/dds-cleaning-tape)

## DDS-3 drive

Model: IBM STD224000N (internal drive). Cannot find any tech specs on it.

When it is connected to the machine, on bootup it shows:

    Time-out failure during SCSI inquiry command

Then after a few more tries the screen goes blank and the machine hangs.


From [SCSI controller docs](http://download.adaptec.com/pdfs/installation_guides/scsi_installation_and_user_guide_02_07.pdf):

>- Internal Ultra320, Ultra160, and Ultra2 SCSI LVD devices come from the factory with termination disabled and cannot be changed. Proper termination for these internal devices is provided by the built-in terminator at the end of the 68-pin internal LVD SCSI cable.
>- Termination on SE internal SCSI devices is usually controlled by manually setting a jumper or a switch on the device, or by physically removing or installing one or more resistor modules on the device.

So could be a termination issue ...

UPDATE: it seems this [IBM 7206-110](http://www.dich.com.tw/Product/Storage/Tape/IBM/7206%20Model%20110%2012%20GB%20External%204mm%20DDS-3%20Tape%20Drive.pdf) external drive is basically the external variant of this drive. See also [here](ftp://ftp.software.ibm.com/software/server/firmware/12GB4mm.htm).