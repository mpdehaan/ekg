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

import re
import copy

from urllib import urlopen, urlretrieve
from re import compile
from os import makedirs
from os.path import join

import sqlalchemy

from sqlalchemy import create_engine, Table, MetaData, Table, Column,\
    Integer, Text, DateTime
from sqlalchemy.exceptions import InvalidRequestError
from sqlalchemy.orm import mapper, sessionmaker, scoped_session, relation
from sqlalchemy.schema import ForeignKey, UniqueConstraint
from sqlalchemy.ext.declarative import declarative_base

from util import iter_in_transaction, pwd

engine = create_engine('sqlite:///sqllite.db')
metadata = MetaData()
Session = scoped_session(sessionmaker(autoflush=False, bind=engine))
Base = declarative_base(metadata=metadata)

stream_classes = dict()

def register_stream(cls, name):
    global stream_classes
    stream_classes[name] = cls

def unique(item):
    item._unique = True
    return sql_attribute(item)

def sql_attribute(item):
    item._sql_attribute = True
    return item
    
# has to be subclassed from type(Base) because it has to be a direct child
class MetaSqlBase(type):
    def __init__(cls, name, bases, attrs):
        sql_attrs = dict()
        unique_sql_attrs = dict()
        for attr in dir(cls):
            if isinstance(getattr(cls, attr), Column) \
                    or getattr(getattr(cls, attr), "_sql_attribute", False):
                sql_attrs[attr] = True
        for attr in sql_attrs.iterkeys():
            if getattr(getattr(cls, attr), "_unique", False):
                unique_sql_attrs[attr] = True
        cls._validate_remote = cls._clear_inv_keys_func(sql_attrs)
        cls._unique_remote = cls._clear_inv_keys_func(unique_sql_attrs)
        if not hasattr(cls, '__mapper_args__'):
            cls.__mapper_args__ = dict()
        cls.__mapper_args__['polymorphic_identity'] = name.lower()
        super(MetaSqlBase, cls).__init__(name, bases, attrs)

    def _clear_inv_keys_func(self, v_keys):
        def clear_inv_keys(remote):
            v_remote = copy.copy(remote)
            for key in remote.iterkeys():
                if key not in v_keys:
                    del v_remote[key]
            print 'using keys:'
            print v_keys
            print v_remote
            return v_remote
        return staticmethod(clear_inv_keys)
            

class SqlBase(object):
    __metaclass__ = MetaSqlBase
    @classmethod
    def create_or_update(cls, **keys):
        try:
            sql_obj = session.query(cls)\
                .filter_by(**cls._unique_remote(keys))\
                .one()
        except InvalidRequestError, e:
            sql_obj = cls(**cls._validate_remote(keys))
            session.add(sql_obj)
        return sql_obj

class MetaObject(MetaSqlBase, type(Base)):
    pass

# has to be subclassed from type(SqlBase) because it has to be a direct child
class MetaStream(type(Base), MetaSqlBase):
    def __init__(cls, name, bases, attrs):
        source = name.lower()
        cls.source = source
        super(MetaStream, cls).__init__(name, bases, attrs)
        register_stream(cls, source)


class Stream(SqlBase, Base):
    __metaclass__ = MetaStream
    __tablename__ = 'streams'
    id = Column('id', Integer, primary_key=True)
    type = Column('type', Text, nullable=False)
    name = Column('name', Text)
    __mapper_args__ = dict(polymorphic_on = type)
    __table_args__ = (UniqueConstraint(type, name))


    def outofdate_sources_iter(self, remotes):
        for remote in iter_in_transaction(session, remotes):
            remote['stream'] = self
            remote['identifier'] = remote['mbox']
            source_obj = Source.create_or_update(**remote)
            if source_obj.needs_update(remote):
                yield source_obj, remote

    def refresh_sources_list(self):
        print self.source
        print self.name
        with pwd(CACHE_DIR):
            try:
                makedirs(self.cache)
            except OSError, e:
                print e
            remotes = self.remote_iter()
            for source, remote in \
                    iter_in_transaction(session, self.outofdate_sources_iter(remotes)):
                source.update(remote)
    
    def load_remote_list(self):
        raise NotImplementedError

    @property
    def cache(self):
        return join(self.source, self.name)


class Mailman(Stream):
    # should it be mailmans or mailmen?
    __tablename__ = 'mailmen'
    id = Column('id', Integer, ForeignKey('streams.id'), primary_key=True)

    def remote_iter(self):
        site = self.archive
        html = urlopen(site).read()
        matches = self.regex.finditer(html)
        match_dicts = (match.groupdict() for match in matches)
        for match_dict in match_dicts:
            match_dict['url'] = self.url(match_dict['mbox'])
            if type(match_dict['size']) is str:
                match_dict['size'] = int(match_dict['size'])
            yield match_dict

        
    @property
    def archive(self):
        raise NotImplementedError

    @property
    def listinfo(self):
        raise NotImplementedError

    def url(self, month):
        raise NotImplementedError

    def mbox(self, month):
        print 'deprecated usage'
        return self.url(month)

    def cached_source(self, month):
        return join(self.cache, month)

class RHMailman(Mailman):
    __tablename__ = 'rhmailmen'
    id = Column('id', Integer, ForeignKey('mailmen.id'), primary_key=True)
    __mapper_args__ = dict(inherits=Mailman)

    regex = compile(r"""<td>(?P<month>\d{4}-.*?):</td>.*td><a href="(?P<mbox>(?P=month)\.txt\.gz).*?Gzip'd Text (?P<size>\d.*?) bytes""", re.I | re.S)

    @property
    def archive(self):
        return 'https://www.redhat.com/archives/%s/' % self.name

    @property
    def listinfo(self):
        return 'https://www.redhat.com/mailman/listinfo/%s/' % self.name

    def url(self, month):
        return self.archive + month


class FHMailman(Mailman):
    __tablename__ = 'fhmailman'
    id = Column('id', Integer, ForeignKey('mailmen.id'), primary_key=True)
    __mapper_args__ = dict(inherits=Mailman)

    regex = compile(r"""<td>(?P<month>\w*?) (?P<year>\d{4}):</td>.*?<A href="(?P<mbox>(?P=year)-(?P=month).txt.gz)".*?text (?P<size>\d.*?) (KB|bytes)""", re.I | re.S)

    @property
    def archive(self):
        return 'https://fedorahosted.org/pipermail/%s/' % self.name

    @property
    def listinfo(self):
        return 'https://fedorahosted.org/mailman/listinfo/%s/' % self.name

    def url(self, month):
        return self.archive + month

class FPMailman(Mailman):
    __tablename__ = 'fpmailmen'
    id = Column('id', Integer, ForeignKey('mailmen.id'), primary_key=True)
    __mapper_args__ = dict(inherits=Mailman)

    regex = compile(r"""<td>(?P<month>\w*?) (?P<year>\d{4}):</td>.*?<A href="(?P<mbox>(?P=year)-(?P=month).txt.gz)".*?text (?P<size>\d.*?)KB""", re.I | re.S)

    @property
    def archive(self):
        return 'http://lists.fedoraproject.org/pipermail/%s/' % self.name

    @property
    def listinfo(self):
        return 'https://admin.fedoraproject.org/mailman/listinfo/%s' % self.name

    def url(self, month):
        return self.archive + month

class Source(SqlBase, Base):
    __metaclass__ = MetaObject
    __tablename__ = 'sources'
    id      = Column('id', Integer, primary_key=True)
#     source  = Column('source', Text, index=True)
#     list    = Column('list', Text, index=True)
    cache_file    = Column('cache_file', Text)
    cache_url = Column('cache_url', Text)
    size    = Column('size', Integer)
    identifier   = Column('identifier', Text)
    stream_id = Column('stream_id', Integer,
                       ForeignKey('streams.id'), index=True, unique=True)
    stream = relation(Stream, primaryjoin=stream_id==Stream.id,
                      backref='sources')
    __table_args__ = (UniqueConstraint('stream_id', 'identifier'),{})

    def needs_update(self, remote):
        return not self.size == remote['size'] or UPDATE_ALL

    def update(self, remote):
        self.url = remote['url']
        self.cache_source(self.url)
        self.size = remote['size']
        with pwd(self.cache_location):
            mbox = self.mbox
#         with session.begin():
        for email in iter_in_transaction(mbox):
            Fact.create_or_update(source, **email)

    def cache_source(self):
        location = self.cache_location
        url_loc = urlretrieve(self.url, location)

    @property
    def cache_location(self):
        return join(self.stream.cache, self.cache_file)

    # This needs to be abstracted a bit
    @property
    def mbox(self):
        path_in = self.cache_file
        f_in = gzip.open(path_in, 'rb')
        path_out = path_in.replace('.gz', '')
        f_out = open(path_out, 'wb')
        f_out.writelines(f_in)
        f_out.close()
        return mailbox.mbox(path_out)

class Fact(SqlBase, Base):
    __metaclass__ = MetaObject
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

#     @classmethod
#     def create_or_update(cls, **keys):
#         message_id = keys['Message-ID']
#         sender = keys['From']
#         source = keys['source']
#         try:
#             # this should be a unique enough query i think
#             email_obj = session.query(cls).filter_by(message=message_id,
#                                                      sender=sender,
#                                                      source=source).one()
#         except InvalidRequestError, e:
#             email_obj = cls(source=source,
#                             message=message_id)
#             email_obj.sender = keys['From']
#             # sometimes these fields are blank, which is kinda ok, because it's a garbage message
#             # but dateutil can't handle None, so we have to use this hack
#             email_obj.date = dateutil.parser.parse(keys['Date'] or str(datetime.datetime.min))
#             email_obj.subject = keys['Subject']
#             session.add(email_obj)
#         return email_obj

session = Session()

__all__ = ['Source', 'Fact', 'session', 'Session', 'metadata', 'engine', 'stream_classes']
