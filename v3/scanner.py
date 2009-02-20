# Copyright 2009, Red Hat, Inc
# Copyright 2009, Yaakov Nemoy
#
# This software may be freely redistributed under the terms of the GNU
# general public license, version 2 or higher.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

import gzip
import mailbox

from sqlalchemy.exceptions import InvalidRequestError

from configobj import ConfigObj
from urllib import urlopen, urlretrieve
from os.path import join
from os import mkdir

import mailman
from model import *

UPDATE_ALL = False

def read_gzip_mbox(path):
    f_in = gzip.open(path, 'rb')
    path_out = path.replace('.gz', '')
    f_out = open(path_out, 'wb')
    f_out.writelines(f_in)
    f_out.close()
    print path_out
    return mailbox.mbox(path_out)

def retrieve_mbox(mm, mbox):
    url = mm.mbox(mbox.mbox)
    location = mbox.archive
    url_loc = urlretrieve(url, location)
    print url_loc

def update_mbox(location):
    return read_gzip_mbox(location)

def main():
    print 'in main'
#     mm = mailman.RHMailman('fedora-devel-list')
    mm = mailman.FHMailman('cobbler')
    mb_lists = mm.mbox_lists()
    to_update = list()
    print mb_lists
    try:
        mkdir('cobbler')
    except OSError, e:
        print e
    for mb in mb_lists:
        if type(mb['size']) is str:
            mb['size'] = int(mb['size'])
        try:
            mbox = session.query(MBox).filter_by(mbox = mb['mbox'], 
                                                 list='cobbler').one()
        except InvalidRequestError, e:
            mbox = MBox(list='cobbler', 
                        mbox=mb['mbox'], 
                        month=mb['month'], 
                        size=0)
            session.save(mbox)
        if not mbox.size == mb['size'] or UPDATE_ALL:
            retrieve_mbox(mm, mbox)
            mbox.size = mb['size']
        to_update.append(mbox)
    session.commit()
    print to_update
    for mbox in to_update:
        print update_mbox(mbox.archive)

if __name__ == '__main__':
    main()
