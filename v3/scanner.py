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

def read_gzip_mbox(path):
    f_in = gzip.open(path, 'rb')
    path_out = path.replace('.gz', '')
    f_out = open(path_out, 'wb')
    f_out.writelines(f_in)
    f_out.close()
    return mailbox.mbox(path_out)

def retrieve_mbox(mbox_url, source):
    print 'retrieve mbox'
    print source.archive
    print mbox_url
    location = source.archive
    url_loc = urlretrieve(mbox_url, location)
    print url_loc

def update_email(email, source):
    message_id = email['Message-ID']
    sender = email['From']
    try:
        # this should be a unique enough query i think
        email_obj = session.query(Fact).filter_by(message=message_id,
                                                  sender=sender,
                                                  source=source).one()
    except InvalidRequestError, e:
        email_obj = Fact(source=source,
                         message=message_id)
        email_obj.sender = email['From']
        # sometimes these fields are blank, which is kinda ok, because it's a garbage message
        # but dateutil can't handle None, so we have to use this hack
        email_obj.date = dateutil.parser.parse(email['Date'] or str(datetime.datetime.min))
        email_obj.subject = email['Subject']
    session.save_or_update(email_obj)

def update_mbox(source):
    with util.pwd(CACHE_DIR):
        mbox = read_gzip_mbox(source.archive)
    with session.begin():
        for email in mbox:
            update_email(email, source)
    return mbox

def load_mbox(mbox):
    print mbox
    try:
        source = session.query(Source)\
            .filter_by(cache_file=mbox['mbox'],
                       source=mbox['source'],
                       list=mbox['list'])\
            .one()
        print 'source prexisting'
    except InvalidRequestError, e:
        source = Source(source=mbox['source'],
                        list=mbox['list'],
                        cache_file=mbox['mbox'],
                        cache_url=mbox['mbox_url'],
                        month=mbox['month'],
                        size=0)
        print 'new source'
        session.save(source)
    return source
    

def load_mboxes(mm):
    mb_lists = mm.mbox_lists()
    print mb_lists
    with session.begin():
        for mb in mb_lists:
            print mb
            yield load_mbox(mb), mb

def lists_to_update(mboxes):
    for source, mbox in mboxes:
        print 'checking for updates'
        print source, mbox
        if needs_update(source, mbox):
            yield source

def needs_update(source, mbox):
    if not source.size == mbox['size'] or UPDATE_ALL:
        retrieve_mbox(mbox['mbox_url'], source)
        source.size = mbox['size']
        return True
    return False


def update_list(name, mailman_class):
    mm = mailman_class(name=name)
    with util.pwd(CACHE_DIR):
        try:
            makedirs(mm.cache)
        except OSError, e:
            print e
        mb_list = load_mboxes(mm)
        to_update = lists_to_update(mb_list)
        for mbox in to_update:
            print 'updating mbox in main ', mbox
            print update_mbox(mbox)
    session.commit()


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
