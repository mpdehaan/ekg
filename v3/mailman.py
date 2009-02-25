# Copyright 2009, Red Hat, Inc
# Copyright 2009, Yaakov Nemoy
#
# This software may be freely redistributed under the terms of the GNU
# general public license, version 2 or higher.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

import re

from urllib import urlopen, urlretrieve
from re import compile
from os.path import join


class Mailman(object):
    def __init__(self, list):
        self.list = list

    def mbox_lists(self):
        site = self.archive
        html = urlopen(site).read()
        matches = self.regex.finditer(html)
        return [match.groupdict() for match in matches]

    @property
    def archive(self):
        raise NotImplementedError

    @property
    def listinfo(self):
        raise NotImplementedError

    def mbox(self, month):
        raise NotImplementedError

    @property
    def cache(self):
        return join(self.source, self.list)

    def cached_mbox(self, month):
        return join(self.cache, month)

class RHMailman(Mailman):
    regex = compile(r"""<td>(?P<month>\d{4}-.*?):</td>.*td><a href="(?P<mbox>(?P=month)\.txt\.gz).*?Gzip'd Text (?P<size>\d.*?) bytes""", re.I | re.S)
    source = 'redhat'

    @property
    def archive(self):
        return 'https://www.redhat.com/archives/%s/' % self.list

    @property
    def listinfo(self):
        return 'https://www.redhat.com/mailman/listinfo/%s/' % self.list

    def mbox(self, month):
        return self.archive + month


class FHMailman(Mailman):
    regex = compile(r"""<td>(?P<month>\w*?) (?P<year>\d{4}):</td>.*?<A href="(?P<mbox>(?P=year)-(?P=month).txt.gz)".*?text (?P<size>\d.*?)KB""", re.I | re.S)
    source = 'fedorahosted'

    @property
    def archive(self):
        return 'https://fedorahosted.org/pipermail/%s/' % self.list

    @property
    def listinfo(self):
        return 'https://fedorahosted.org/mailman/listinfo/%s/' % self.list

    def mbox(self, month):
        return self.archive + month
