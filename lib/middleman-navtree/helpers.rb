module Middleman
  module NavTree
    # NavTree-related helpers that are available to the Middleman application in +config.rb+ and in templates.
    module Helpers
      #  A recursive helper for converting source tree data from into HTML
      def tree_to_html(value, depth = Float::INFINITY, key = nil, level = 0, hide_directory_index: false)
        html = ''
        active = nil

        if value.is_a?(String)
          # This is a file.
          # Get the Sitemap resource for this file.
          # note: sitemap.extensionless_path converts the path to its 'post-build' extension.
    
          if this_resource = find_resource_by_path(value)
            active = this_resource == current_page ? ' active' : nil

            title  = discover_title(this_resource)
            link   = link_to(title, this_resource)
            html << "<li class='child#{active}'>#{link}</li>"
          end
        else
          value = Hash[value.sort_by { |key, path| sort_info(key, path) }]

          # This is the first level source directory. We treat it special because
          # it has no key and needs no list item.
          if key.nil?
            value.each do |newkey, child|
              child_content, child_active =
                tree_to_html(child, depth, newkey, level + 1,
                             hide_directory_index: hide_directory_index)
              html << child_content
              active ||= child_active
            end
            # Continue rendering deeper levels of the tree, unless restricted by depth.
          elsif depth >= (level + 1)
            # This is a directory.
            # The directory has a key and should be listed in the page hieararcy with HTML.
            contents = ""
            directory_name, active = format_directory_name(key, value)

            # Loop through all the directory's contents.
            value.each do |newkey, child|
              next if hide_directory_index && (newkey == 'directory_index')
              child_content, child_active =
                tree_to_html(child, depth, newkey, level + 1,
                             hide_directory_index: hide_directory_index)
              contents << child_content
              active ||= child_active
            end
            html << "<li class='parent#{active}'><span class='parent-label'>#{directory_name}</span>"
            html << '<ul>'
            html << contents
            html << '</ul>'
            html << '</li>'
          end
        end

        if level == 0
          return html
        else
          return html, active
        end
      end

      def sort_info(key, path)
        if path.kind_of?(Hash) && (index_path = path['directory_index'])
          if page = find_resource_by_path(index_path)
            if info = page.data[:directory_sort_info]
              return info
            end
          end
        end

        if path.kind_of?(String) 
          if page = find_resource_by_path(path)
            if info = page.data[:sort_info]
              return info
            end
          end
        end

        if key == 'directory_index'
          0
        else 1000
        end
      end

      # Pagination helpers
      # @todo: One potential future feature is previous/next links for paginating on a
      #        single level instead of a flattened tree. I don't need it but it seems pretty easy.
      def previous_link(sourcetree)
        pagelist = flatten_source_tree(sourcetree)
        position = get_current_position_in_page_list(pagelist)
        # Skip link generation if position is nil (meaning, the current page isn't in our
        # pagination pagelist).
        if position
          prev_page = pagelist[position - 1]
          options = {:class => "previous"}
          unless first_page?(pagelist)
            link_to(I18n.t("previous_page", default: 'Previous'), prev_page, options)
          end
        end
      end

      def next_link(sourcetree)
        pagelist = flatten_source_tree(sourcetree)
        position = get_current_position_in_page_list(pagelist)
        # Skip link generation if position is nil (meaning, the current page isn't in our
        # pagination pagelist).
        if position
          next_page = pagelist[position + 1]
          options = {:class => "next"}
          unless last_page?(pagelist)
            link_to(I18n.t("next_page", default: 'Next'), next_page, options)
          end
        end
      end

      # Helper for use in pagination methods.
      def first_page?(pagelist)
        return true if get_current_position_in_page_list(pagelist) == 0
      end

      # Helper for use in pagination methods.
      def last_page?(pagelist)
        return true if pagelist[get_current_position_in_page_list(pagelist)] == pagelist[-1]
      end

      # Method to flatten the source tree, for use in pagination methods.
      def flatten_source_tree(value, k = [], level = 0, flat_tree = [])
        if value.is_a?(String)
          # This is a child item (a file).
          flat_tree.push(sitemap.extensionless_path(value))
        elsif value.is_a?(Hash)
          # This is a parent item (a directory).
          value.each do |key, child|
            flatten_source_tree(child, key, level + 1, flat_tree)
          end
        end

        return flat_tree
      end

      # Helper for use in pagination methods.
      def get_current_position_in_page_list(pagelist)
        pagelist.each_with_index do |page_path, index|
          if page_path == "/" + current_page.path
            return index
          end
        end
        # If we reach this line, the current page path wasn't in our page list and we'll
        # return false so the link generation is skipped.
        return FALSE
      end

      # Format Directory name for display in navtree.
      # Example Name: 1%20-%20sink-or_swim
      def format_directory_name(dir_name, children)
        if directory_index_path = children["directory_index"]
          if directory_index_page = find_resource_by_path(directory_index_path)
            active = directory_index_path == current_page ? ' active' : nil
            title  = directory_index_page.data.directory_title ||
              discover_title(directory_index_page)
            link   = link_to(title, directory_index_page)
            return link, active
          end
        end

        formatted_name = dir_name.gsub('%20', ' ') #=> 1 - sink-or_swim
        formatted_name.gsub!(/(?!\s)-(?!\s)/, ' ') #=> 1 - sink or_swim
        formatted_name.gsub!(/_/, ' ') #=> 1 - sink or swim
        # @todo: Find a way for titleize to not blow away ' - ' formatting.
        return formatted_name.titleize!, nil #=> 1 Sink or Swim
      end

      # Utility helper for getting the page title for display in the navtree.
      # Based on this: http://forum.middlemanapp.com/t/using-heading-from-page-as-title/44/3
      # 1) Use the title from frontmatter metadata, or
      # 2) peek into the page to find the H1, or
      # 3) Use the home_title option (if this is the home page--defaults to "Home"), or
      # 4) fallback to a filename-based-title
      def discover_title(page = current_page)
        if page.data.title
          return page.data.title # Frontmatter title
        elsif match = page.render({:layout => false, :no_images => true}).match(/<h.+>(.*?)<\/h1>/)
          return match[1] # H1 title
        elsif page.url == '/'
          return extensions[:navtree].options[:home_title]
        else
          filename = page.url.split(/\//).last.gsub('%20', ' ').titleize
          return filename.chomp(File.extname(filename))
        end
      end

      def find_resource_by_path(path)
        # Make sure the extension path ends with .html (in case we're parsing someting like .adoc)
        extensionlessPath = sitemap.extensionless_path(path)
        unless extensionlessPath.end_with? ".html"
         extensionlessPath << ".html"
        end
        
        sitemap.find_resource_by_path(extensionlessPath)
      end
    end
  end
end
