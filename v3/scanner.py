# Copyright 2009, Red Hat, Inc
# Copyright 2009, Yaakov Nemoy
#
# This software may be freely redistributed under the terms of the GNU
# general public license, version 2 or higher.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
from __future__ import with_statement

import gzip
import mailbox
import datetime
import dateutil.parser

from sqlalchemy.exceptions import InvalidRequestError

from configobj import ConfigObj
from urllib import urlopen, urlretrieve
from os.path import join
from os import makedirs

import util
from model import *

UPDATE_ALL = True
CACHE_DIR = '.'

def main():
    print 'in main'
    metadata.create_all(engine)
    config = ConfigObj('settings.ini')
    print config['lists']
    global CACHE_DIR
    global UPDATE_ALL
    CACHE_DIR = config['cache_dir']
    UPDATE_ALL = config['update_all']
    for list, source in config['lists'].items():
        mailman_class = stream_classes[source]
        update_list(list, mailman_class)
#     update_list('fedora-wiki', mailman.FPMailmain)
#     update_list('cobbler', mailman.FHMailman)

if __name__ == '__main__':
    main()
