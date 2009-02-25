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
from contextlib import contextmanager
from os import chdir, getcwd

@contextmanager
def pwd(dir):
    old_dir = getcwd()
    print 'changing dir to %s' % dir
    chdir(dir)
    yield
    print 'changing dir to %s' % old_dir
    chdir(old_dir)

