
--##########################################################################--
--[[----------------------------------------------------------------------]]--
-- app object
--[[----------------------------------------------------------------------]]--
--##########################################################################--
local app = {}
app.init = false
app.data_finished = false

-- timing
app.clock = nil
app.real_clock = nil        -- time_scale is always 1
app.event_manager = nil

-- running date/time
app.date_x = 300
app.date_y = 0
app.date_str = ''
app.date_height = 50
app.progress_height = 7

-- data files
app.filenames = nil         -- list of filenames as strings
app.start_time = nil
app.end_time = nil

-- master timer
app.min_time_scale = 0
app.max_time_scale = 2000
app.default_time_scale = 2000
app.time_slider = nil
app.clock = nil
app.current_time = nil
app.current_day = 0

-- tweet data
app.current_file = 0        -- filenames index
app.tweets = nil
app.current_tweet = nil     -- index of tweet in app.tweets
app.current_time = nil
app.tweets_per_hit = 1     -- how many tweets until a hit is reported
app.hit_count = 0
app.hits = nil
app.max_latest_tweets = 50
app.latest_tweets = nil
app.terms = nil
app.num_terms = 0

-- hashtag data
app.hashtags = nil                -- hash table of hashtag objects indexed by 
                                  -- lowercase hashtag
app.hashtag_count = 0
app.max_top_tags = 25
app.hashtag_cleanup_time = 1.25
app.hashtag_cleanup_timer = nil
app.hashtag_sort_time = 0.1
app.hashtag_sort_timer = nil
app.min_top_tag_count = 5        -- minimum hashtag count to be recognized as
                                 -- a top hashtag
app.top_hashtags = nil
app.top_x = 75
app.top_y = 100

-- sorting options
app.sort_by = 1
app.SORT_BY_TOP = 1               -- total number of mentions
app.SORT_BY_RATE = 2              -- highest mention rate at current time
app.SORT_BY_TOP_RATE = 3          -- highest mention rate over entire time
app.sort_labels = {"Count", "Trending", "Top Activity"}

-- bar chart
app.chart = nil
app.chart_x = 300
app.chart_y = 100
app.chart_width = 900
app.chart_height = 300

-- twitter_feed
app.twitter_feed = nil
app.feed_x = 300
app.feed_y = 500
app.feed_width = 1100
app.feed_height = 300

-- mouse input
app.last_press_mx = nil
app.last_press_my = nil
app.mx = 0
app.my = 0
app.mouse_isdown = false

-- canvas
app.panel = nil
app.panel_x = 0
app.panel_y = 0
app.wheel_step = 10

-- documents
app.documents_init = false
app.documents = nil

-- data saving
app.step_time = 100
app.next_step_time = 0
app.step_count = 0
app.archive = nil
app.blank_points = nil


local app_mt = { __index = app }
function app:new(file_list)
  local clock = master_timer:new()
  local real_clock = master_timer:new()
  
  local callback = app._time_slider_changed
  local max = app.max_time_scale
  local min = app.min_time_scale
  local slider = gui_slider:new(20, 100, 40, SCR_HEIGHT - 200, 
                                min, max, callback, "")
                                
  slider:set_value(app.default_time_scale)
  clock:set_time_scale(app.default_time_scale)
  
  local cleanup_timer = timer:new(real_clock, self.hashtag_cleanup_time)
  cleanup_timer:start()
  
  local sort_timer = timer:new(real_clock, self.hashtag_sort_time)
  sort_timer:start()
  
  -- calculate file end time (in seconds)
  -- Note: will be calculated incorrectly if data rolls over to the next month
  -- fix later
  local first_file = require(file_list[1])
  local last_file = require(file_list[#file_list])
  local first_day = string.sub(first_file[1].time.date, 1, 2)
  local last_day = string.sub(last_file[#last_file].time.date, 1, 2)
  local days_passed = tonumber(last_day) - tonumber(first_day)
  local start_time = first_file[1].time.seconds
  local start_day = string.sub(first_file[1].time.date, 1, 2)
  local start_month = string.sub(first_file[1].time.date, 4, 6)
  local start_hour = string.sub(first_file[1].time.time, 1, 2)
  local start_minute = string.sub(first_file[1].time.time, 4, 5)
  local start_second = string.sub(first_file[1].time.time, 7, 8)
  local end_time = last_file[#last_file].time.seconds + days_passed * 24*60 * 60
  self.next_step_time = start_time + self.step_time
  self.sort_by = 2
  
  local event_manager = event_manager:new()
  
  local flash_curve_points = require('curves/curve_flash')
  local curve = curve:new(flash_curve_points, 200)
  
  local left_arrow_bbox = bbox:new(90, 72, 30, 30)
  local right_arrow_bbox = bbox:new(230, 72, 30, 30)
  
  -- canvas
  local panel = love.graphics.newCanvas(SCR_WIDTH, 2000)
  
  object = setmetatable({ filenames = file_list,
                          start_time = start_time,
                          start_day = start_day,
                          start_month = start_month,
                          start_hour = start_hour,
                          start_minute = start_minute,
                          start_second = start_second,
                          end_time = end_time,
                          clock = clock,
                          real_clock = real_clock,
                          time_slider = slider,
                          latest_tweets = {},
                          terms = {},
                          hashtags = {},
                          top_hashtags = {},
                          hashtag_cleanup_timer = cleanup_timer,
                          hashtag_sort_timer = sort_timer,
                          event_manager = event_manager,
                          top_hashtags = {},
                          hashtag_flash_curve = curve,
                          left_arrow_bbox = left_arrow_bbox,
                          right_arrow_bbox = right_arrow_bbox,
                          panel = panel,
                          documents = {},
                          archive = {},
                          blank_points = {}}, app_mt)
                          
  slider.parent = object
  
  -- initialize chart
  local title = "Tweet Frequency vs Time for "
  local title_highlight = "All Tweets"
  local hits = {}
  local x, y = app.chart_x, app.chart_y
  local width, height = app.chart_width, app.chart_height
  local fast_start_curve = require('curves/curve_fast-start')
  local bin_curve = curve:new(fast_start_curve, 200)
  chart = bar_chart:new(object, x, y, width, height, 
                        start_time, end_time, hits, bin_curve, 
                        title, title_highlight)
  chart:display()
  
  object.chart = chart
  object.hits = hits
  
  -- initialize tweet feed
  local x, y = self.feed_x, self.feed_y
  local width, height = self.feed_width, self.feed_height
  local twitter_feed = twitter_feed:new(object, x, y, width, height, 
                                        object.latest_tweets, font_text, bin_curve)
  object.twitter_feed = twitter_feed
  
  return object
end

function app:_init()
  self:_load_data_file(self.filenames[1])
  self.current_file = 1
  self.clock:set_time(self.file_start_time)
  self.current_time = self.clock:get_time()
  self.init = true
end

function app:_save_data()
  self.step_count = self.step_count + 1
  self.next_step_time = self.current_time + self.step_time
  
  local start_t, end_t = self.start_time, self.end_time
  local time_progress = (self.current_time - start_t) / (end_t - start_t)
  time_progress = math.min(time_progress, 1)
  
  local blanks = self.blank_points
  local p = {}
  p.x, p.y = time_progress, 0
  blanks[#blanks + 1] = p
  
  local top_tags = self.top_hashtags
  if #top_tags == 0 then
    return
  end
  
  local archive = self.archive
  for i=1,#top_tags do
    local tag = top_tags[i]
    
    if archive[tag] then
      local data = archive[tag]
      local points = data.points
      local rate = tag:_update_rate()
      
      local point = {}
      point.x = time_progress
      point.y = rate
      points[#points + 1] = point
    else
      local data = {}
      data.tag = tag
      data.points = {}
      
      local blanks = self.blank_points
      for i=1,#blanks-1 do
        local point = {}
        point.x = blanks[i].x
        point.y = blanks[i].y
        data.points[#data.points + 1] = point
      end
      
      local rate = tag:_update_rate()
      local point = {}
      point.x = time_progress
      point.y = rate
      data.points[#data.points+1] = point
      
      archive[tag] = data
    end
  end
  
end

function app:_init_archive_data()
  local archive_data = {}
  local archive = self.archive
  
  for tag, data in pairs(archive) do
    local points = data.points
    local spline = cubic_spline:new(points)
    
    local max = 0
    for i=0,1,0.01 do
      local val = spline:get_val(i)
      if val > max then
        max = val
      end
    end
    
    local data = {}
    data.hashtag = tag
    data.spline = spline
    data.max = max
    
    archive_data[#archive_data + 1] = data
  end
  
  self.archive_data = archive_data
  DATA_INITIALIZED = true
  init_visuals()
end

function app:mousepressed(x, y, button)

  if button == 'l' then
    self.last_press_mx = x
    self.last_press_my = y
    self.mouse_isdown = true
  end
  
  -- arrow pressed
  if button == 'l' then
    local sortno = self.sort_by
    local mpos = vector2:new(self.mx, self.my)
    if     self.left_arrow_bbox:contains_point(mpos) then
      sortno = sortno - 1
      sortno = math.max(1, sortno)
    elseif self.right_arrow_bbox:contains_point(mpos) then
      sortno = sortno + 1
      sortno = math.min(3, sortno)
    end
    
    self.sort_by = sortno
  end
  
  
  self.chart:mousepressed(x - self.panel_x, y - self.panel_y, button)
  
  if button == 'wd' then
    self.panel_y = self.panel_y - self.wheel_step
  end
  if button == 'wu' then
    self.panel_y = self.panel_y + self.wheel_step
    if self.panel_y > SCR_HEIGHT - 200 then
      self.panel_y = SCR_HEIGHT - 200
    end
  end
end

function app:mousereleased(x, y, button)

  if button == 'l' then
  
    -- check if user clicked a hashtag
    local top = self.top_hashtags
    for i=1,#top do
      if top[i]:check_mouse(x, y) then
        local title = "Tweet Frequency vs Time for "
        self.chart:set_hit_data(top[i].hits)
        self.chart:set_title(title, "#"..top[i].name)
        self.chart:display()
        
        self.twitter_feed:set_tweet_data(top[i].tweet_list)
        
        for j=1,#top do
          top[j].selected = false
        end
        top[i].selected = true
        
        break
      end
    end
    
    self.mouse_isdown = false
  end
  
  self.chart:mousereleased(x, y, button)
end

function app:_time_slider_changed(name, value)
  self:set_time_scale(value)
end

function app:_load_data_file(filename)
  local tweets = require(filename)
  
  -- When a day rolls over in the data, the seconds count resets to 0
  -- Must keep track of days rolled over so a days worth of seconds can be added
  -- to tweet.time.seconds
  local day = self.current_day
  local secs_per_day = 60 * 60 * 24
  local start_time = tweets[1].time.seconds + day * secs_per_day
  local end_time = tweets[#tweets].time.seconds + day * secs_per_day
  
  -- Case where day rolls over during this file.
  if end_time < start_time then
    self.current_day = self.current_day + 1
    
    for i=1,#tweets do
      local t = tweets[i].time.seconds
      if t <= end_time then
        tweets[i].time.seconds = t + (day + 1) * secs_per_day
      else
        tweets[i].time.seconds = t + day * secs_per_day
      end
      
    end
    
    end_time = end_time + self.current_day * secs_per_day
    
  -- Case where day is consistent throughout entire file
  else
    for i=1,#tweets do
      tweets[i].time.seconds = tweets[i].time.seconds + day * secs_per_day
    end
  end
  
  -- Twitter stream give time precision to the second
  -- Since animation runs at 60fps, we must interpolate between second values so 
  -- tweets appear to stream continuously
  i = 1
  while (i < #tweets) do
    local tweet = tweets[i]
    local seconds = tweet.time.seconds
    
    j = i + 1
    while j < #tweets do
      local new_seconds = tweets[j].time.seconds
      if new_seconds ~= seconds then
        break
      end
      
      j = j + 1
    end
    
    local timestep = 1 / (j-i)
    idx = 0
    for k=i,j-1 do
      tweets[k].time.seconds = tweets[k].time.seconds + idx * timestep
      idx = idx + 1
    end
    
    i = j
  end
  
  self.file_start_time = start_time
  self.file_end_time = end_time
  self.tweets = tweets
  self.current_tweet = 1
end

function app:_load_next_data_file()
  local file_idx = self.current_file + 1
  
  if file_idx > #self.filenames then
    return false
  end
  
  self:_load_data_file(self.filenames[file_idx])
  self.current_file = file_idx
  
  return true
end

function app:_get_next_tweets()
  local time = self.current_time
  local idx = self.current_tweet
  local tweets = self.tweets
  local next_tweets = {}
  
  -- CASE 1: all upcoming tweets are in the current file
  if time <= self.file_end_time then
    while true do
      if tweets[idx].time.seconds <= time then
        next_tweets[#next_tweets + 1] = tweets[idx]
        idx = idx + 1
      else
        self.current_tweet = idx
        break
      end
    end
  end
  
  -- CASE 2: upcoming tweets are in current and next file
  if time > self.file_end_time then

    -- rest of tweets in current file
    for i=idx,#tweets do
      next_tweets[#next_tweets + 1] = tweets[i]
    end
    
    local success = self:_load_next_data_file()
    if not success then
      return next_tweets, false
    end
    
    -- upcoming tweets in the next file
    local tweets = self.tweets
    local idx = self.current_tweet
    
    while true do 
    
      if tweets[idx].time.seconds <= time then
        next_tweets[#next_tweets + 1] = tweets[idx]
        idx = idx + 1
        
        if idx > #tweets then
          print("ERROR")
          print("idx: "..idx)
          print("tweets len: "..#tweets)
          print(tweets[#tweets].time.seconds)
          
          self.current_tweet = idx - 1
          break
        end
      else
        self.current_tweet = idx
        break
      end
    end 
  end
  
  return next_tweets, true
end


function app:_process_hashtag(tag, tweet)
  local hashtags = self.hashtags
  local lower_tag = string.lower(tag)
  
  if hashtags[lower_tag] then
    hashtags[lower_tag]:add_tweet(tweet)
  else
    local new_hashtag = hashtag:new(self, tag, self.hashtag_flash_curve)
    new_hashtag:add_tweet(tweet)
    hashtags[lower_tag] = new_hashtag
  end
  
  return hashtags[lower_tag]
end

local common_words = COMMON_WORDS
function app:_process_terms(tweet, tags)
  local text = tweet.text
  local term_list = self.terms
  
  local sep = "%s"
  local terms = string.gmatch(text, "([^"..sep.."]+)")
  for v in terms do
    if not (string.sub(v,1,1) == "#") then
      v = v:gsub('%W',''):lower()
      if not common_words[v] and not tonumber(v) and #v > 1 then
        if term_list[v] then
          term_list[v] = term_list[v] + 1
        else
          term_list[v] = 1
          self.num_terms = self.num_terms + 1
        end
        
        for i=1,#tags do
          tags[i]:add_term(v)
        end
        
      end
    end
  end
  
end

function app:_process_tweet(tweet)

  local hashtags = tweet.hashtags
  local processed_tags = {}
  local tweet_tags = {}
  for i=1,#hashtags do
    if not processed_tags[hashtags[i]] then
      tweet_tags[#tweet_tags+1] = self:_process_hashtag(hashtags[i], tweet)
      processed_tags[hashtags[i]] = true
    end
  end
  
  self:_process_terms(tweet, tweet_tags)

  --print(tweet.time.time, tweet.text)
  self.hit_count = self.hit_count + 1
  if self.hit_count >= self.tweets_per_hit then
    self.hits[#self.hits + 1] = tweet.time.seconds
    self.hit_count = 0
  end
  
  local tweets = self.latest_tweets
  table.insert(tweets, 1, tweet)
  if #tweets > self.max_latest_tweets then
    table.remove(tweets, #tweets)
  end
  
  -- check if it's time to save
  local time = tweet.time.seconds
  if time > self.next_step_time then
    self:_save_data()
  end
  
end

function app:set_time_scale(scale)
  self.clock:set_time_scale(scale)
end

function app:_init_documents()
  -- find hashtags that qualify as documents
  local documents = {}
  local hit_threshold = 20
  local hashtags = self.hashtags
  for _,v in pairs(hashtags) do
    if #v.hits > hit_threshold then
      documents[#documents + 1] = v
    end
  end
  
  -- find terms that qualify as document terms
  local document_terms = {}
  local term_threshold = 20
  local terms = self.terms
  local doc_term_count = 0
  for term,count in pairs(terms) do
    if count > term_threshold then
      document_terms[term] = count
      doc_term_count = doc_term_count + 1
    end
  end
  
  -- initialize document terms for hashtag documents
  for i=1,#documents do
    documents[i]:init_document(document_terms)
  end
  
  -- find inverse document frequency
  local idf = {}
  local N = #documents
  for term,count in pairs(document_terms) do
    local ni = 0
    for i=1,#documents do
      local doc = documents[i]
      if doc.document_terms[term] then
        ni = ni + 1
      end
    end
    
    if ni == 0 then
      ni = 1
    end
    
    idf[term] = math.log10(N / ni) * 3.3219
  end
  
  -- find tf * idf for each document
  for i=1,#documents do
    documents[i]:init_tfidf(idf)
  end

  self.documents_init = true
end

------------------------------------------------------------------------------
function app:update(dt)
  if not self.init then self:_init() end
  
  if self.data_finished and not self.documents_init then
    self:_init_documents()
    self:_init_archive_data()
  end
  
  self.mx, self.my = love.mouse.getPosition()    
  self.chart:set_mouse_position(self.mx - self.panel_x, self.my - self.panel_y)
  
  self.time_slider:update(dt)
  
  self.clock:update(dt)
  self.real_clock:update(dt)
  self.current_time = self.clock:get_time()
  
  -- find and process next tweets
  if not self.data_finished then
    next_tweets, is_more_data = self:_get_next_tweets()
    if not is_more_data then
      self.data_finished = true
      print("Reached end of data")
    end
    
    for _,tweet in ipairs(next_tweets) do
      self:_process_tweet(tweet)
    end
  end
  
  self:_update_hashtags(dt)
  self.event_manager:update(dt)
  self:update_date(dt)
  self.chart:update(dt)
  self.twitter_feed:update(dt)
  
  if self.data_finished then
    self.clock:set_time_scale(0)
  end
  
end

function app:update_date()
  local last_tweet = self.tweets[self.current_tweet]
  local date = last_tweet.time.date
  local time = last_tweet.time.time
  self.date_string = string.upper(date.." "..time.." ".."(GMT)")
  
  local width = font_large:getWidth(self.date_string)
  self.date_x = 0.5 * SCR_WIDTH - 0.5 * width
  
end

function app:_update_hashtags(dt)
  local hashtags = self.hashtags
  
  for _,tag in pairs(hashtags) do
    tag:update(dt)
  end
  
  -- remove expired tags
  if self.hashtag_cleanup_timer:progress() == 1 then
    local count = 0
    for key,hashtag in pairs(hashtags) do
      if hashtag:is_expired() then
        hashtags[key] = nil
      end
      count = count + 1
    end
    self.hashtag_count = count
    
    self.hashtag_cleanup_timer:start()
  end
  
  -- sort and find top hashtags
  -- remove expired tags
  if self.hashtag_sort_timer:progress() == 1 then
    self.top_hashtags = self:_get_top_hashtags()
    self.hashtag_sort_timer:start()
  end
  
  -- check if mouse is on any top tags
  local mx, my = love.mouse.getPosition()
  local top = self.top_hashtags
  for i=1,#top do
    top[i]:check_mouse(mx, my)
  end
  
end

function app:_get_top_hashtags()
  -- find potential top hashtags
    local hashtags = self.hashtags
    local candidates = {}
    local min = self.min_top_tag_count
    local idx = 1
    
    local sort_by = self.sort_by
    if     sort_by == self.SORT_BY_TOP then
      for key,hashtag in pairs(hashtags) do
        if hashtag.count >= min then
          candidates[idx] = {hashtag.count, hashtag.id}
          idx = idx + 1
        end
      end
    elseif sort_by == self.SORT_BY_RATE then
      for key,hashtag in pairs(hashtags) do
        if hashtag.count >= min and hashtag.rate > 0 then
          candidates[idx] = {hashtag.rate, hashtag.id}
          idx = idx + 1
        end
      end
    elseif sort_by == self.SORT_BY_TOP_RATE then
      for key,hashtag in pairs(hashtags) do
        if hashtag.count >= min and hashtag.rate > 0 then
          candidates[idx] = {hashtag.max_rate, hashtag.id}
          idx = idx + 1
        end
      end
    end
    
    -- sort
    local top_tags = {}
    local max = self.max_top_tags
    if #candidates > 0 then
      table.sort(candidates, function(a,b) return a[1]<b[1] end)
      
      for i=#candidates,#candidates-math.min(max, #candidates-1),-1 do
        top_tags[#top_tags + 1] = hashtags[candidates[i][2]]
      end
      self.top_hashtags = top_tags
      
      -- set position of tags
      local x, y = self.top_x, self.top_y
      local ystep = 30
      for i=1,#top_tags do
        top_tags[i]:set_position(x, y + (i-1) * ystep)
      end
      
      -- set scores
      local max = candidates[#candidates][1]
      for i=1,#top_tags do
        if     sort_by == self.SORT_BY_TOP then
          top_tags[i]:set_score(top_tags[i].count / max)
        elseif sort_by == self.SORT_BY_RATE then
          top_tags[i]:set_score(top_tags[i].rate / max)
        elseif sort_by == self.SORT_BY_TOP_RATE then
          top_tags[i]:set_score(top_tags[i].max_rate / max)
        end 
        top_tags[i]:set_position(x, y + (i-1) * ystep)
      end
      
    end
    
    return top_tags
end

------------------------------------------------------------------------------
function app:draw()

  if not self.data_finished then
  
    local start_t, end_t = self.start_time, self.end_time
    local percent = math.floor(((self.current_time - start_t) / (end_t - start_t)) * 100)
    local text = "Loading Stream: "..tostring(percent)..'%'..' complete'
    local x = 0.5 * SCR_WIDTH - 0.5 * font_large:getWidth(text)
    local y = 0.5 * SCR_HEIGHT - 0.5 * font_large:getHeight(text) - 100
    lg.setFont(font_large)
    lg.setColor(C_DARK_GREEN)
    lg.print(text, x, y)

    return
  end
  
  -- draw time and date bar
  --[[
  lg.setColor(C_DARKER_GREY)
  lg.rectangle('fill', 0, 0, SCR_WIDTH, self.date_height)
  lg.setColor(C_ORANGE)
  lg.setFont(font_large)
  lg.print(self.date_string, self.date_x, self.date_y)
  ]]--
  
  -- progress bar
  --[[
  local start_t, end_t = self.start_time, self.end_time
  local progress = (self.current_time - start_t) / (end_t - start_t)
  local width, height = progress * SCR_WIDTH, self.progress_height
  lg.setColor(C_ORANGE)
  lg.rectangle('fill', 0, self.date_height - height, width, height)
  
  self.time_slider:draw()
  ]]--
  
  --[[
  -- top hashtags
  local top = self.top_hashtags
  local selected = nil
  for i=1,#top do
    top[i]:draw()
    if top[i].selected then
      selected = top[i]
    end
  end
  
  if selected then
    local x, y = 0, 0
    selected:draw_term_bubbles(self.panel_x + 350, self.panel_y + 500)
  end
  
  -- draw sort options
  local label = self.sort_labels[self.sort_by]
  local width = 200
  local x = self.top_x + 0.5 * width - 0.5 * font_smallest:getWidth(label)
  local y = self.top_y - 20
  
  lg.setFont(font_smallest)
  lg.setColor(C_RED)
  lg.print(label, x, y)
  
  local text = "Order by"
  x = self.top_x + 0.5 * width - 0.5 * font_smallest:getWidth(text)
  lg.setColor(C_DARK_RED)
  lg.print(text, x, y - 20)
  
  if #top == 0 then
    local text = "waiting for data..."
    x = self.top_x + 0.5 * width - 0.5 * font_smallest:getWidth(text)
    local y = self.top_y + 100
    lg.setColor(200, 200, 200,255)
    lg.print(text, x, y)
  end
  
  -- draw arrows
  local mpos = vector2:new(self.mx, self.my)
  
  if self.left_arrow_bbox:contains_point(mpos) then
    lg.setColor(C_RED)
  else
    lg.setColor(C_GREEN)
  end
  if self.sort_by == 1 then
    lg.setColor(C_DARKER_GREY)
  end
  
  local x, y = self.top_x + 20, self. top_y - 20
  local aw = 15
  local ah = 15
  local points = {x, y + 0.5 * ah, x + aw, y, x + aw, y + ah}
  lg.polygon("fill", points)
  
  if self.right_arrow_bbox:contains_point(mpos) and self.sort_by <= 2 then
    lg.setColor(C_RED)
  else
    lg.setColor(C_GREEN)
  end
  if self.sort_by == 3 then
    lg.setColor(C_DARKER_GREY)
  end
  
  local x, y = self.top_x + width - 20, self. top_y - 20
  local aw = 15
  local ah = 15
  local points = {x - aw, y, x - aw, y + ah, x, y + 0.5*ah}
  lg.polygon("fill", points)
  
  local panel = self.panel
  panel:clear()
  lg.setCanvas(panel)
  self.chart:draw()
  lg.setCanvas()
  
  lg.setColor(255, 255, 255, 255)
  lg.draw(panel, self.panel_x, self.panel_y)
  --self.twitter_feed:draw()
  ]]--
  
end

return app














