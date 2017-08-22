# FIXME: using the storage-ng in Travis is still needed while the merge of
# storage-ng and master is not complete. It should be switched to YaST standard
# docker image soon.
FROM yastdevel/ruby
COPY . /usr/src/app

