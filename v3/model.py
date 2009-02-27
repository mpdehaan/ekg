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

import sqlalchemy

from sqlalchemy import create_engine, Table, MetaData, Table, Column,\
    Integer, Text, DateTime
from sqlalchemy.orm import mapper, sessionmaker, scoped_session, relation
from sqlalchemy.schema import ForeignKey
from sqlalchemy.ext.declarative import declarative_base

engine = create_engine('sqlite:///sqllite.db')
metadata = MetaData()
Session = scoped_session(sessionmaker(transactional=True, autoflush=False, bind=engine))
Base = declarative_base(metadata=metadata)

stream_classes = dict()

def register_stream(cls, name):
    global stream_classes
    stream_classes[name] = cls


# has to be subclassed from type(Base) because it has to be a direct child
class MetaStream(type(Base)):
    def __init__(cls, name, bases, attrs):
        super(MetaStream, cls).__init__(name, bases, attrs)
        print cls.__init__
        source = name.lower()
        register_stream(cls, source)
        if not hasattr(cls, '__mapper_args__'):
            cls.__mapper_args__ = dict()
        cls.__mapper_args__['polymorphic_identity'] = source
        cls.source = source


class Stream(Base):
    __metaclass__ = MetaStream
    __tablename__ = 'streams'
    id = Column('id', Integer, primary_key=True)
    type = Column('type', Text, nullable=False)
    name = Column('name', Text)
    __mapper_args__ = dict(polymorphic_on = type)
    pass


class Mailman(Stream):
    def mbox_lists(self):
        site = self.archive
        html = urlopen(site).read()
        matches = self.regex.finditer(html)
        match_dicts = [match.groupdict() for match in matches]
        for match_dict in match_dicts:
            match_dict['mbox_url'] = self.mbox(match_dict['mbox'])
            match_dict['list'] = self.name
            match_dict['source'] = self.source
            if type(match_dict['size']) is str:
                match_dict['size'] = int(match_dict['size'])
        return match_dicts

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
        return join(self.source, self.name)

    def cached_mbox(self, month):
        return join(self.cache, month)

class RHMailman(Mailman):
    regex = compile(r"""<td>(?P<month>\d{4}-.*?):</td>.*td><a href="(?P<mbox>(?P=month)\.txt\.gz).*?Gzip'd Text (?P<size>\d.*?) bytes""", re.I | re.S)

    @property
    def archive(self):
        return 'https://www.redhat.com/archives/%s/' % self.name

    @property
    def listinfo(self):
        return 'https://www.redhat.com/mailman/listinfo/%s/' % self.name

    def mbox(self, month):
        return self.archive + month


class FHMailman(Mailman):
    regex = compile(r"""<td>(?P<month>\w*?) (?P<year>\d{4}):</td>.*?<A href="(?P<mbox>(?P=year)-(?P=month).txt.gz)".*?text (?P<size>\d.*?) (KB|bytes)""", re.I | re.S)

    @property
    def archive(self):
        return 'https://fedorahosted.org/pipermail/%s/' % self.name

    @property
    def listinfo(self):
        return 'https://fedorahosted.org/mailman/listinfo/%s/' % self.name

    def mbox(self, month):
        return self.archive + month

class FPMailman(Mailman):
    regex = compile(r"""<td>(?P<month>\w*?) (?P<year>\d{4}):</td>.*?<A href="(?P<mbox>(?P=year)-(?P=month).txt.gz)".*?text (?P<size>\d.*?)KB""", re.I | re.S)

    @property
    def archive(self):
        return 'http://lists.fedoraproject.org/pipermail/%s/' % self.name

    @property
    def listinfo(self):
        return 'https://admin.fedoraproject.org/mailman/listinfo/%s' % self.name

    def mbox(self, month):
        return self.archive + month

class Source(Base):
    __tablename__ = 'sources'
    id      = Column('id', Integer, primary_key=True)
#     source  = Column('source', Text, index=True)
#     list    = Column('list', Text, index=True)
    cache_file    = Column('cache_file', Text)
    cache_url = Column('cache_url', Text)
    size    = Column('size', Integer)
    month   = Column('month', Text)
    stream_id = Column('stream_id', Integer,
                       ForeignKey('streams.id'), index=True)
    stream = relation(Stream, primaryjoin=stream_id==Stream.id,
                      backref='sources')

    @property
    def archive(self):
        return join(self.source, self.list, self.cache_file)

class Fact(Base):
    __tablename__ = 'facts'
    id      = Column('id', Integer, primary_key=True)
    sender  = Column('sender', Text, index=True)
    message = Column('message_id', Text, index=True)
    date    = Column('date', DateTime)
    subject = Column('subject', Text)
    source_id = Column('source_id', Integer,
                       ForeignKey('sources.id'), index=True)
    source = relation(Source, primaryjoin=source_id==Source.id,
                      backref='facts')

session = Session()

__all__ = ['Source', 'Fact', 'session', 'Session', 'metadata', 'engine', 'stream_classes']
