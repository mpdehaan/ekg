# Copyright 2009, Red Hat, Inc
# Copyright 2009, Yaakov Nemoy
#
# This software may be freely redistributed under the terms of the GNU
# general public license, version 2 or higher.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

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

class Source(Base):
    __tablename__ = 'sources'
    id      = Column('id', Integer, primary_key=True)
    source  = Column('source', Text, index=True)
    list    = Column('list', Text, index=True)
    cache_file    = Column('cache_file', Text)
    cache_url = Column('cache_url', Text)
    size    = Column('size', Integer)
    month   = Column('month', Text)

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

metadata.create_all(engine)
session = Session()

__all__ = ['Source', 'Fact', 'session', 'Session', 'metadata', 'engine']
