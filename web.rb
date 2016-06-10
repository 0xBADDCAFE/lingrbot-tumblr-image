require 'sinatra'
require 'sinatra/reloader' if development?
require 'tumblr_client'
require 'redis'

# Authenticate via API Key
TUMBLR_CLIENT = Tumblr::Client.new :consumer_key => ENV['API_KEY']
REDIS         = Redis.new(:url => ENV['REDIS_URL'])

# Make the request
all_user = Hash.new
# posts = Array.new
# offset = 0
# fetch = TUMBLR_CLIENT.posts 'kuroboshi-kouhaku.tumblr.com', :type => 'photo'
# while fetch['posts'].length > 0 do
#   posts.concat(fetch['posts'])
#   offset += fetch['posts'].length
#   fetch = TUMBLR_CLIENT.posts 'kuroboshi-kouhaku.tumblr.com', :type => 'photo', :offset => offset
# end

get '/' do
  'hi'
end

get '/random' do
  gen_image_link get_random_image(all_user[params['id']])
end

get '/newest' do
  gen_image_link get_newest_image(all_user[params['id']])
end

get '/add' do
  p params
  add_id(params['alias'], params['id'])
end

get '/del' do
  p params
  delete_id(params['alias'])
end

get '/list' do
  REDIS.hkeys('id_list').join(', ')
end

post '/lingr' do
  content_type :text
  response = ""

  parsed = JSON.parse(request.body.string)
  parsed['events'].select {|e| e['message']}.map { |e|
    next if settings.development? && e['message']['room'] != 'censored'

    prefix, cmd, *arg = e['message']['text'].split
    if prefix =~ /^#tu?mblr?$/
      # manage ids
      case cmd
      when nil, "help"
        response = "available: add, del/rm, list"
      when "add"
        if arg.length == 2
          response = add_id(arg[0], arg[1]) # get adding result
        elsif arg.length == 1
          response = add_id(arg[0], arg[0]) # get adding result
        else
          response = 'usage: #tmbl add [alias] [id/url]'
        end
      when "del", "rm"
        if arg.length == 1
          response = delete_id(arg[0])
        else
          response = 'usage: #tmbl del [alias]'
        end
      when 'list'
        response = REDIS.hkeys('id_list').join(', ')
      end
    elsif (prefix[0] == '#' \
           && REDIS.hexists('id_list', prefix[1..-1]))
      # each id response
      id = REDIS.hget('id_list', prefix[1..-1])
      posts = Array.new
      case cmd
      when "new"
        posts = fetch_new_posts(id, all_user[id])
        all_user[id] = posts
        response = get_newest_image(posts)
      when 'url'
        response = "http://#{id}.tumblr.com"
      else
        if all_user.has_key? id
          posts = all_user[id]
        else
          posts = fetch_all_posts(id)
          all_user[id] = posts
        end
        response = get_random_image(posts)
      end
    end
  }

  response.strip
end

private
def add_id(alias_str, id_str)
  if id_str =~ /^https?:\/\/([\w-]+)\.tumblr.com/ || id_str =~ /([\w-]+)/
    info = TUMBLR_CLIENT.blog_info $1
    if info.has_key? 'blog'
      alias_name = if alias_str == id_str; $1 else alias_str end
      REDIS.hset('id_list', alias_name, $1)
      r = 'successfully added'
    else
      r = 'the id not found'
    end
  else
    r = 'invalid id/url format'
  end
  r
end

def delete_id(alias_str)
  if REDIS.hdel('id_list', alias_str) > 0
      r = 'successfully deleted'
  else
      r = 'the alias not found'
  end
  r
end

def fetch_all_posts(id)
  posts = Array.new
  offset = 0
  fetch = TUMBLR_CLIENT.posts(id, :type => 'photo')
  while fetch['posts'].length > 0 do
    posts.concat(fetch['posts'])
    offset += fetch['posts'].length
    fetch = TUMBLR_CLIENT.posts(id, :type => 'photo', :offset => offset)
  end
  posts
end

def fetch_new_posts(id, cur_posts)
  return fetch_all_posts(id) if cur_posts.nil?

  posts = Array.new
  offset = 0
  news = TUMBLR_CLIENT.posts(id, :type => 'photo')['posts']

  # debug
  p id, news if news.nil?

  # if posts is 0, do nothing because it might be other bot's command.
  # TODO: but the id has no image should be delete, so I consider to suggest it.
  while news.length > 0 do
    posts.concat(news)
    break if (cur_posts - news).length < cur_posts.length
    offset += news.length
    news = TUMBLR_CLIENT.posts(id, :type => 'photo', :offset => offset)['posts']
    # debug
    p id, news, offset if news.nil?
  end
  (posts + cur_posts).uniq
end

def get_random_image(posts)
  return 'no image posts' if posts.empty?
  posts.sample['photos'].sample['original_size']['url']
end

def get_newest_image(posts)
  return 'no image posts' if posts.empty?
  posts[0]['photos'][0]['original_size']['url']
end

def gen_image_link(url)
  "<img src=#{url}>"
end
