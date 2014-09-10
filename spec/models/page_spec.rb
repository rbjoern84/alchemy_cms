# encoding: UTF-8

require 'spec_helper'

module Alchemy
  describe Page do
    let(:language)      { Language.default }
    let(:klingonian)    { create(:klingonian) }
    let(:parent)        { create(:page, page_layout: 'standard', parent: nil) }
    let(:page)          { build_stubbed(:page, page_layout: 'foo') }
    let(:public_page)   { create(:public_page) }
    let(:news_page)     { create(:public_page, page_layout: 'news', do_not_autogenerate: false) }

    # Validations

    context 'validations' do
      context "Creating a normal content page" do
        let(:contentpage)              { build(:page) }
        let(:with_same_urlname)        { create(:page, urlname: "existing_twice") }
        let(:global_with_same_urlname) { create(:page, urlname: "existing_twice", layoutpage: true) }

        context "when its urlname exists as global page" do
          before { global_with_same_urlname }

          it "it should be possible to save." do
            contentpage.urlname = "existing_twice"
            expect(contentpage).to be_valid
          end
        end

        it "should validate the page_layout" do
          contentpage.page_layout = nil
          expect(contentpage).not_to be_valid
          contentpage.valid?
          expect(contentpage.errors[:page_layout].size).to eq(1)
        end

        context 'with page having same urlname' do
          before { with_same_urlname }

          it "should not be valid" do
            contentpage.urlname = 'existing_twice'
            expect(contentpage).not_to be_valid
          end
        end
      end
    end

    # Callbacks

    describe 'callbacks' do
      let(:page) do
        create(:page, name: 'My Testpage')
      end

      describe '.before_save' do
        it "should not set the title automatically if the name changed but title is not blank" do
          page.name = "My Renaming Test"
          page.save; page.reload
          expect(page.title).to eq("My Testpage")
        end

        it "should not automatically set the title if it changed its value" do
          page.title = "I like SEO"
          page.save; page.reload
          expect(page.title).to eq("I like SEO")
        end
      end

      describe '.after_update' do
        context "urlname has changed" do
          it "should store legacy url" do
            page.urlname = 'new-urlname'
            page.save!
            expect(page.legacy_urls).not_to be_empty
            expect(page.legacy_urls.first.urlname).to eq('my-testpage')
          end

          it "should not store legacy url twice for same urlname" do
            page.urlname = 'new-urlname'
            page.save!
            page.urlname = 'my-testpage'
            page.save!
            page.urlname = 'another-urlname'
            page.save!
            expect(page.legacy_urls.select { |u| u.urlname == 'my-testpage' }.size).to eq(1)
          end

          context 'with children present' do
            let(:child) { create(:page) }

            before do
              page.children << child
              page.save!
              page.reload
            end

            it "updates urlname of children" do
              expect(page.children.first.urlname).to eq("#{page.slug}/#{child.slug}")
              page.update(urlname: 'new-urlname')
              expect(page.children.first.urlname).to eq("new-urlname/#{child.slug}")
            end
          end
        end

        context "urlname has not changed" do
          it "should not store a legacy url" do
            page.urlname = 'my-testpage'
            page.save!
            expect(page.legacy_urls).to be_empty
          end
        end

        context "public has changed" do
          it "should update published_at" do
            expect {
              page.update_attributes!(public: true)
            }.to change {page.read_attribute(:published_at) }
          end

          it "should not update already set published_at" do
            page.update_attributes!(published_at: 2.weeks.ago)
            expect {
              page.update_attributes!(public: true)
            }.to_not change { page.read_attribute(:published_at) }
          end
        end

        context "public has not changed" do
          it "should not update published_at" do
            page.update_attributes!(name: 'New Name')
            expect(page.read_attribute(:published_at)).to be_nil
          end
        end
      end

      context 'after parent changes' do
        let(:parent_1) { create(:page, name: 'Parent 1') }
        let(:parent_2) { create(:page, name: 'Parent 2') }
        let(:page)     { create(:page, parent_id: parent_1.id, name: 'Page') }

        it "updates the urlname" do
          expect(page.urlname).to eq('parent-1/page')
          page.parent_id = parent_2.id
          page.save!
          expect(page.urlname).to eq('parent-2/page')
        end
      end

      context "a normal page" do
        let(:page) { build(:page, language_code: nil, language: klingonian) }

        it "should set the language code" do
          page.save!
          expect(page.language_code).to eq("kl")
        end

        context 'with do_not_autogenerate set to false' do
          before { page.do_not_autogenerate = false }

          it "should autogenerate the elements" do
            page.save!
            expect(page.elements).to_not be_empty
          end

          context 'with elements already on the page' do
            before do
              page.elements << create(:element, name: 'header')
              page.save!
              page.reload
            end

            it "should not autogenerate these elements" do
              expect(page.elements.select { |e| e.name == 'header' }.length).to eq(1)
            end
          end
        end

        context "with cells" do
          let(:page_with_cells) { create(:page, page_layout: 'with_cells', do_not_autogenerate: false) }

          before do
            allow(PageLayout).to receive(:get).and_return({
              'name' => 'with_cells',
              'cells' => %w(header),
              'elements' => %w(article),
              'autogenerate' => %w(article)
            })
          end

          context 'with cell definitions has the same elements listed' do
            before do
              allow(Cell).to receive(:all_definitions_for).and_return([{
                'name' => 'header',
                'elements' => %w(article)
              }])
            end

            it "should have the generated elements in their cells" do
              expect(page_with_cells.cells.where(name: 'header').first.elements).to_not be_empty
            end
          end

          context "and no elements in cell definitions" do
            before do
              allow(page).to receive(:cell_definitions).and_return([{
                'name' => 'header',
                'elements' => []
              }])
            end

            it "should have the elements in the nil cell" do
              expect(page.cells.collect(&:elements).flatten).to be_empty
            end
          end
        end

        context "with a restricted parent" do
          let(:child) { build(:page, parent: page) }

          before do
            page.update!(restricted: true)
          end

          it "should also be restricted" do
            child.save!
            expect(child.restricted?).to be_truthy
          end
        end

        context 'after updating the restricted status' do
          let!(:child_1) { create(:page, restricted: false) }
          let!(:child_2) { create(:page, restricted: false) }

          it "all children should inherit that status" do
            child_1.children << child_2
            page.children << child_1
            page.update!(restricted: true)
            child_1.reload
            expect(child_1.restricted?).to be_truthy
            child_2.reload
            expect(child_2.restricted?).to be_truthy
          end
        end

        context "with do_not_autogenerate set to true" do
          let(:page) { create(:page, do_not_autogenerate: true) }

          it "should not autogenerate the elements" do
            expect(page.elements).to be_empty
          end
        end
      end

      context "after changing the page layout" do
        let(:news_element) { news_page.elements.find_by(name: 'news') }

        it "all elements not allowed on this page should be trashed" do
          expect(news_page.elements.trashed).to be_empty
          news_page.update_attributes(page_layout: 'standard')
          trashed = news_page.elements.trashed.pluck(:name)
          expect(trashed).to eq(['news'])
          expect(trashed).to_not include('article', 'header')
        end

        it "should autogenerate elements" do
          news_page.update_attributes(page_layout: 'contact')
          expect(news_page.elements.pluck(:name)).to include('contactform')
        end
      end

      describe 'after_create' do
        let(:root_node) { Node.root }
        let(:page)      { build(:page) }

        context 'with #create_node set to true' do
          before { page.create_node = true }

          it "creates a node for page" do
            page.save!
            expect(page.nodes).to_not be_empty
          end

          context 'with parent page that has a node' do
            let!(:parent)      { create(:page) }
            let!(:parent_node) { Node.create!(name: 'Parent node', navigatable: parent, language: Language.default) }

            before do
              parent_node.move_to_child_of(root_node)
              page.update!(parent: parent)
            end

            it 'adds the node as child of parent node' do
              expect(page.nodes.first.parent).to eq(parent_node)
            end
          end

          context 'with no parent page' do
            it 'puts the node into the first navigation tree' do
              page.save!
              expect(page.nodes.first.parent).to eq(root_node)
            end
          end

          it 'names the node after page name' do
            page.save!
            expect(page.nodes.first.name).to eq(page.name)
          end
        end
      end
    end

    # ClassMethods (a-z)

    describe '.all_from_clipboard_for_select' do
      context "with clipboard holding pages having non unique page layout" do
        it "should return the pages" do
          page_1 = create(:page, language: language)
          page_2 = create(:page, language: language, name: 'Another page')
          clipboard = [
            {'id' => page_1.id.to_s, 'action' => 'copy'},
            {'id' => page_2.id.to_s, 'action' => 'copy'}
          ]
          expect(Page.all_from_clipboard_for_select(clipboard, language.id)).to include(page_1, page_2)
        end
      end

      context "with clipboard holding a page having unique page layout" do
        it "should not return any pages" do
          page_1 = create(:page, :language => language, :page_layout => 'contact')
          clipboard = [
            {'id' => page_1.id.to_s, 'action' => 'copy'}
          ]
          expect(Page.all_from_clipboard_for_select(clipboard, language.id)).to eq([])
        end
      end

      context "with clipboard holding two pages. One having a unique page layout." do
        it "should return one page" do
          page_1 = create(:page, language: language, page_layout: 'standard')
          page_2 = create(:page, name: 'Another page', language: language, page_layout: 'contact')
          clipboard = [
            {'id' => page_1.id.to_s, 'action' => 'copy'},
            {'id' => page_2.id.to_s, 'action' => 'copy'}
          ]
          expect(Page.all_from_clipboard_for_select(clipboard, language.id)).to eq([page_1])
        end
      end
    end

    describe '.all_locked' do
      it "should return 1 page that is blocked by a user at the moment" do
        create(:public_page, locked: true, name: 'First Public Child', language: language)
        expect(Page.all_locked.size).to eq(1)
      end
    end

    describe '.all_locked_by' do
      let(:user) { double(:user, id: 1, class: DummyUser) }

      before do
        FactoryGirl.create(:public_page, locked: true, locked_by: 53) # This page must not be part of the collection
        allow(user.class)
          .to receive(:primary_key)
          .and_return('id')
      end

      it "should return the correct page collection blocked by a certain user" do
        page = FactoryGirl.create(:public_page, locked: true, locked_by: 1)
        expect(Page.all_locked_by(user).pluck(:id)).to eq([page.id])
      end

      context 'with user class having a different primary key' do
        let(:user) { double(:user, user_id: 123, class: DummyUser) }

        before do
          allow(user.class)
            .to receive(:primary_key)
            .and_return('user_id')
        end

        it "should return the correct page collection blocked by a certain user" do
          page = FactoryGirl.create(:public_page, locked: true, locked_by: 123)
          expect(Page.all_locked_by(user).pluck(:id)).to eq([page.id])
        end
      end
    end

    describe '.contentpages' do
      let!(:layoutpage)  { create(:page, name: 'layoutpage', layoutpage: true) }
      let!(:contentpage) { create(:page, name: 'contentpage') }

      it "returns a collection of contentpages" do
        expect(Page.contentpages.to_a).to include(contentpage)
      end

      it "contains no layoutpages" do
        expect(Page.contentpages.to_a).to_not include(layoutpage)
      end
    end

    describe '.copy' do
      let(:page) { create(:page, name: 'Source') }

      subject { Page.copy(page) }

      it "the copy should have added (copy) to name" do
        expect(subject.name).to eq("#{page.name} (Copy)")
      end

      context "page with tags" do
        before { page.tag_list = 'red, yellow'; page.save }

        it "the copy should have source tag_list" do
          # The order of tags varies between postgresql and sqlite/mysql
          # This is related to acts-as-taggable-on v.2.4.1
          # To fix the spec we sort the tags until the issue is solved (https://github.com/mbleigh/acts-as-taggable-on/issues/363)
          expect(subject.tag_list).not_to be_empty
          expect(subject.tag_list.sort).to eq(page.tag_list.sort)
        end
      end

      context "page with elements" do
        before { page.elements << create(:element) }

        it "the copy should have source elements" do
          expect(subject.elements).not_to be_empty
          expect(subject.elements.count).to eq(page.elements.count)
        end
      end

      context "page with trashed elements" do
        before do
          page.elements << create(:element)
          page.elements.first.trash!
        end

        it "the copy should not hold a copy of the trashed elements" do
          expect(subject.elements).to be_empty
        end
      end

      context "page with cells" do
        before { page.cells << create(:cell) }

        it "the copy should have source cells" do
          expect(subject.cells).not_to be_empty
          expect(subject.cells.count).to eq(page.cells.length) # It must be length, because!
        end
      end

      context "page with autogenerate elements" do
        before do
          page = create(:page)
          allow(page).to receive(:definition).and_return({'name' => 'standard', 'elements' => ['headline'], 'autogenerate' => ['headline']})
        end

        it "the copy should not autogenerate elements" do
          expect(subject.elements).to be_empty
        end
      end

      context "with different page name given" do
        subject { Page.copy(page, {name: 'Different name'}) }
        it "should take this name" do
          expect(subject.name).to eq('Different name')
        end
      end
    end

    describe '.create' do
      context "before/after filter" do
        it "should automatically set the title from its name" do
          page = create(:page, name: 'My Testpage')
          expect(page.title).to eq('My Testpage')
        end

        it "should get a webfriendly urlname" do
          page = create(:page, name: 'klingon$&stößel ')
          expect(page.urlname).to eq('klingon-stoessel')
        end

        context "with no name set" do
          it "should not set a urlname" do
            page = Page.create(name: '')
            expect(page.urlname).to be_blank
          end
        end

        it "should generate a three letter urlname from two letter name" do
          page = create(:page, name: 'Au')
          expect(page.urlname).to eq('-au')
        end

        it "should generate a three letter urlname from two letter name with umlaut" do
          page = create(:page, name: 'Aü')
          expect(page.urlname).to eq('aue')
        end

        it "should generate a three letter urlname from one letter name" do
          page = create(:page, name: 'A')
          expect(page.urlname).to eq('--a')
        end

        it "should add a user stamper" do
          page = create(:page, name: 'A')
          expect(page.class.stamper_class.to_s).to eq('DummyUser')
        end

        context "with language given" do
          it "does not set the language from parent" do
            expect_any_instance_of(Page).not_to receive(:set_language_from_parent_or_default)
            Page.create!(name: 'A', parent_id: parent.id, page_layout: 'standard', language: language)
          end
        end

        context "with no language given" do
          it "sets the language from parent" do
            expect_any_instance_of(Page).to receive(:set_language_from_parent_or_default)
            Page.create!(name: 'A', parent_id: parent.id, page_layout: 'standard')
          end
        end
      end
    end

    describe '.layoutpages' do
      it "returns layoutpages" do
        create(:public_page, layoutpage: true, name: 'Layoutpage')
        expect(Page.layoutpages.size).to eq(1)
      end
    end

    describe '.link_target_options' do
      it "returns an array suitable for options_for_select helper" do
        expect(Page.link_target_options).to eq(
          [["Same Window", ""], ["New Window/Tab", "blank"]]
        )
      end
    end

    describe '.not_locked' do
      it "returns pages that are not locked by another user" do
        create(:public_page, locked: true)
        create(:public_page, locked: false)
        expect(Page.not_locked.size).to eq(1)
      end
    end

    describe '.not_restricted' do
      it "returns public accessible pages" do
        create(:public_page, restricted: true)
        create(:public_page, restricted: false)
        expect(Page.not_restricted.size).to eq(1)
      end
    end

    describe '.public' do
      it "returns public pages" do
        create(:public_page)
        create(:public_page)
        expect(Page.published.size).to eq(2)
      end
    end

    describe '.restricted' do
      it "returns restricted pages" do
        create(:public_page, restricted: true)
        create(:public_page, restricted: false)
        expect(Page.restricted.size).to eq(1)
      end
    end

    # InstanceMethods (a-z)

    describe '#alchemy_node_url' do
      it "returns the urlname" do
        expect(page.alchemy_node_url).to eq(page.urlname)
      end
    end

    describe '#available_element_definitions' do
      let(:page) { build_stubbed(:public_page) }

      it "returns all element definitions of available elements" do
        expect(page.available_element_definitions).to be_an(Array)
        expect(page.available_element_definitions.collect { |e| e['name'] }).to include('header')
      end

      context "with unique elements already on page" do
        let(:element) { build_stubbed(:unique_element) }

        before do
          allow(page)
            .to receive(:elements)
            .and_return double(not_trashed: double(pluck: [element.name]))
        end

        it "does not return unique element definitions" do
          expect(page.available_element_definitions.collect { |e| e['name'] }).to include('article')
          expect(page.available_element_definitions.collect { |e| e['name'] }).not_to include('header')
        end
      end

      context 'limited amount' do
        let(:page) { build_stubbed(:page, page_layout: 'columns') }
        let(:unique_element) { build_stubbed(:unique_element, name: 'unique_headline') }
        let(:element_1) { build_stubbed(:element, name: 'column_headline') }
        let(:element_2) { build_stubbed(:element, name: 'column_headline') }
        let(:element_3) { build_stubbed(:element, name: 'column_headline') }

        before {
          allow(Element).to receive(:definitions).and_return([
            {
              'name' => 'column_headline',
              'amount' => 3,
              'contents' => [{'name' => 'headline', 'type' => 'EssenceText'}]
            },
            {
              'name' => 'unique_headline',
              'unique' => true,
              'amount' => 3,
              'contents' => [{'name' => 'headline', 'type' => 'EssenceText'}]
            }
          ])
          allow(PageLayout).to receive(:get).and_return({
            'name' => 'columns',
            'elements' => ['column_headline', 'unique_headline'],
            'autogenerate' => ['unique_headline', 'column_headline', 'column_headline', 'column_headline']
          })
          allow(page).to receive(:elements).and_return double(
            not_trashed: double(pluck: [
              unique_element.name,
              element_1.name,
              element_2.name,
              element_3.name
            ])
          )
        }

        it "should be readable" do
          element = page.element_definitions_by_name('column_headline').first
          expect(element['amount']).to be 3
        end

        it "should limit elements" do
          expect(page.available_element_definitions.collect { |e| e['name'] }).not_to include('column_headline')
        end

        it "should be ignored if unique" do
          expect(page.available_element_definitions.collect { |e| e['name'] }).not_to include('unique_headline')
        end
      end
    end

    describe '#available_element_names' do
      let(:page) { build_stubbed(:page) }

      it "returns all names of elements that could be placed on current page" do
        page.available_element_names == %w(header article)
      end
    end

    describe '#cache_key' do
      let(:page) do
        stub_model(Page, updated_at: Time.now, published_at: Time.now - 1.week)
      end

      subject { page.cache_key }

      before do
        expect(Page).to receive(:current_preview).and_return(preview)
      end

      context "when current page rendered in preview mode" do
        let(:preview) { page }

        it { is_expected.to eq("alchemy/pages/#{page.id}-#{page.updated_at}") }
      end

      context "when current page not in preview mode" do
        let(:preview) { nil }

        it { is_expected.to eq("alchemy/pages/#{page.id}-#{page.published_at}") }
      end
    end

    describe '#cell_definitions' do
      let(:page) { build(:page, :page_layout => 'foo') }
      let(:cell_descriptions) { [{'name' => "foo_cell", 'elements' => ["1", "2"]}] }

      before do
        allow(page).to receive(:layout_description).and_return({
          'name' => "foo",
          'cells' => ["foo_cell"]
        })
        allow(Cell).to receive(:definitions).and_return(cell_descriptions)
      end

      it "should return all cell definitions for its page_layout" do
        expect(page.cell_definitions).to eq(cell_descriptions)
      end

      it "should return empty array if no cells defined in page layout" do
        allow(page).to receive(:layout_description).and_return({'name' => "foo"})
        expect(page.cell_definitions).to eq([])
      end
    end

    describe '#contains_feed?' do
      context 'with page layout definition has feed: true' do
        let(:page) { build_stubbed(:page, page_layout: 'news') }

        it { expect(page.contains_feed?).to be_truthy }
      end

      context 'with page layout definition has no feed value' do
        let(:page) { build_stubbed(:page) }

        it { expect(page.contains_feed?).to be_falsey }
      end
    end

    describe '#destroy' do
      context "with trashed but still assigned elements" do
        before { news_page.elements.map(&:trash!) }

        it "should not delete the trashed elements" do
          news_page.destroy
          expect(Element.trashed).not_to be_empty
        end
      end
    end

    describe '#element_definitions' do
      let(:page) { build_stubbed(:page) }

      subject { page.element_definitions }

      before do
        expect(Element).to receive(:definitions).and_return([
          {'name' => 'article'},
          {'name' => 'header'}
        ])
      end

      it "returns all element definitions that could be placed on current page" do
        is_expected.to include({'name' => 'article'})
        is_expected.to include({'name' => 'header'})
      end
    end

    describe '#element_definitions_by_name' do
      let(:page) { build_stubbed(:public_page) }

      context "with no name given" do
        it "returns empty array" do
          expect(page.element_definitions_by_name(nil)).to eq([])
        end
      end

      context "with 'all' passed as name" do
        it "returns all element definitions" do
          expect(Element).to receive(:definitions)
          page.element_definitions_by_name('all')
        end
      end

      context "with :all passed as name" do
        it "returns all element definitions" do
          expect(Element).to receive(:definitions)
          page.element_definitions_by_name(:all)
        end
      end
    end

    describe '#element_definition_names' do
      let(:page) { build_stubbed(:public_page) }

      it "returns all element names defined in page layout" do
        expect(page.element_definition_names).to eq(%w(article header))
      end

      it "returns always an array" do
        allow(page).to receive(:definition).and_return({})
        expect(page.element_definition_names).to be_an(Array)
      end
    end

    describe '#elements_grouped_by_cells' do
      let(:page) { create(:public_page, do_not_autogenerate: false) }

      before do
        allow(PageLayout).to receive(:get).and_return({
          'name' => 'standard',
          'cells' => ['header'],
          'elements' => ['header', 'text'],
          'autogenerate' => ['header', 'text']
        })
        allow(Cell).to receive(:definitions).and_return([{
          'name' => "header",
          'elements' => ["header"]
        }])
      end

      it "should return elements grouped by cell" do
        elements = page.elements_grouped_by_cells
        expect(elements.keys.first).to be_instance_of(Cell)
        expect(elements.values.first.first).to be_instance_of(Element)
      end

      it "should only include elements beeing in a cell " do
        expect(page.elements_grouped_by_cells.keys).not_to include(nil)
      end
    end

    describe '#element_names_from_cells' do
      let(:page) { create(:page, page_layout: 'index', do_not_autogenerate: false) }

      it "returns element names from cell definitions." do
        expect(page.element_names_from_cells).to eq(['search'])
      end
    end

    describe '#element_names_not_in_cell' do
      let(:page) { create(:page, page_layout: 'index', do_not_autogenerate: false) }

      it "returns element names that are not defined in a cell." do
        expect(page.element_names_not_in_cell).to eq(['article'])
      end
    end

    describe '#feed_elements' do
      it "should return all rss feed elements" do
        expect(news_page.feed_elements).not_to be_empty
        expect(news_page.feed_elements).to eq(Element.where(name: 'news').to_a)
      end
    end

    describe '#find_elements' do
      before do
        create(:element, public: false, page: public_page)
        create(:element, public: false, page: public_page)
      end

      context "with show_non_public argument TRUE" do
        it "should return all elements from empty options" do
          expect(public_page.find_elements({}, true).to_a).to eq(public_page.elements.to_a)
        end

        it "should only return the elements passed as options[:only]" do
          expect(public_page.find_elements({only: ['article']}, true).to_a).to eq(public_page.elements.named('article').to_a)
        end

        it "should not return the elements passed as options[:except]" do
          expect(public_page.find_elements({except: ['article']}, true).to_a).to eq(public_page.elements - public_page.elements.named('article').to_a)
        end

        it "should return elements offsetted" do
          expect(public_page.find_elements({offset: 2}, true).to_a).to eq(public_page.elements.offset(2))
        end

        it "should return elements limitted in count" do
          expect(public_page.find_elements({count: 1}, true).to_a).to eq(public_page.elements.limit(1))
        end
      end

      context "with options[:from_cell]" do
        let(:element) { build_stubbed(:element) }

        context "given as String" do
          context 'with elements present' do
            before do
              expect(public_page.cells)
                .to receive(:find_by_name)
                .and_return double(elements: double(offset: double(limit: double(published: [element]))))
            end

            it "returns only the elements from given cell" do
              expect(public_page.find_elements(from_cell: 'A Cell').to_a).to eq([element])
            end
          end

          context "that can not be found" do
            let(:elements) {[]}

            before do
              allow(elements)
                .to receive(:offset)
                .and_return double(limit: double(published: elements))
            end

            it "returns empty set" do
              expect(Element).to receive(:none).and_return(elements)
              expect(public_page.find_elements(from_cell: 'Lolo').to_a).to eq([])
            end

            it "loggs a warning" do
              expect(Rails.logger).to receive(:debug)
              public_page.find_elements(from_cell: 'Lolo')
            end
          end
        end

        context "given as cell object" do
          let(:cell) { build_stubbed(:cell, page: public_page) }

          it "returns only the elements from given cell" do
            expect(cell)
              .to receive(:elements)
              .and_return double(offset: double(limit: double(published: [element])))

            expect(public_page.find_elements(from_cell: cell).to_a).to eq([element])
          end
        end
      end

      context "with show_non_public argument FALSE" do
        it "should return all elements from empty arguments" do
          expect(public_page.find_elements().to_a).to eq(public_page.elements.published.to_a)
        end

        it "should only return the public elements passed as options[:only]" do
          expect(public_page.find_elements(only: ['article']).to_a).to eq(public_page.elements.published.named('article').to_a)
        end

        it "should return all public elements except the ones passed as options[:except]" do
          expect(public_page.find_elements(except: ['article']).to_a).to eq(public_page.elements.published.to_a - public_page.elements.published.named('article').to_a)
        end

        it "should return elements offsetted" do
          expect(public_page.find_elements({offset: 2}).to_a).to eq(public_page.elements.published.offset(2))
        end

        it "should return elements limitted in count" do
          expect(public_page.find_elements({count: 1}).to_a).to eq(public_page.elements.published.limit(1))
        end
      end
    end

    describe '#layout_display_name' do
      let(:page) { build_stubbed(:page) }

      it "returns a translated name for page layout" do
        expect(page.layout_display_name).to eq(I18n.t(page.page_layout, scope: 'page_layout_names'))
      end
    end

    describe '#lock_to!' do
      let(:page) { create(:page) }
      let(:user) { mock_model('DummyUser') }

      it "should set locked to true" do
        page.lock_to!(user)
        page.reload
        expect(page.locked).to eq(true)
      end

      it "should not update the timestamps " do
        expect { page.lock!(user) }.to_not change(page, :updated_at)
      end

      it "should set locked_by to the users id" do
        page.lock_to!(user)
        page.reload
        expect(page.locked_by).to eq(user.id)
      end
    end

    describe '#copy_and_paste' do
      let(:source)      { build_stubbed(:page) }
      let(:new_parent)  { build_stubbed(:page) }
      let(:page_name)   { "Pagename (pasted)" }
      let(:copied_page) { mock_model('Page') }

      subject { Page.copy_and_paste(source, new_parent, page_name) }

      it "should copy the source page with the given name to the new parent" do
        expect(Page).to receive(:copy).with(source, {
          parent_id: new_parent.id,
          language: new_parent.language,
          name: page_name,
          title: page_name
        })
        subject
      end

      it "should return the copied page" do
        allow(Page).to receive(:copy).and_return(copied_page)
        expect(subject).to be_a(copied_page.class)
      end

      context "if source page has children" do
        it "should also copy and paste the children" do
          allow(Page).to receive(:copy).and_return(copied_page)
          allow(source).to receive(:children).and_return([mock_model('Page')])
          expect(source).to receive(:copy_children_to).with(copied_page)
          subject
        end
      end
    end

    # TODO: Delegate Page#next_or_previous to node
    # context 'previous and next methods' do
    #   context 'not attached to node' do
    #     let(:page_without_node) { create(:page) }

    #     it "raises an error" do
    #       expect { page_without_node.previous }.to raise_error
    #       expect { page_without_node.next }.to raise_error
    #     end
    #   end

    #   context 'attached to node' do
    #     let!(:center_page)     { create(:public_page, name: 'Center Page', create_node: true) }
    #     let!(:next_page)       { create(:public_page, name: 'Next Page', create_node: true) }
    #     let!(:non_public_page) { create(:page, name: 'Not public Page', create_node: true) }
    #     let!(:restricted_page) { create(:restricted_page, public: true, create_node: true) }

    #     describe '#previous' do
    #       it "should return the previous page on the same level" do
    #         center_page.previous.should == public_page
    #         next_page.previous.should == center_page
    #       end

    #       context "no previous page on same level present" do
    #         it "should return nil" do
    #           public_page.previous.should be_nil
    #         end
    #       end

    #       context "with options restricted" do
    #         context "set to true" do
    #           it "returns previous restricted page" do
    #             center_page.previous(restricted: true).should == restricted_page
    #           end
    #         end

    #         context "set to false" do
    #           it "skips restricted page" do
    #             center_page.previous(restricted: false).should == public_page
    #           end
    #         end
    #       end

    #       context "with options public" do
    #         context "set to true" do
    #           it "returns previous public page" do
    #             center_page.previous(public: true).should == public_page
    #           end
    #         end

    #         context "set to false" do
    #           it "skips public page" do
    #             center_page.previous(public: false).should == non_public_page
    #           end
    #         end
    #       end
    #     end

    #     describe '#next' do
    #       it "should return the next page on the same level" do
    #         center_page.next.should == next_page
    #       end

    #       context "no next page on same level present" do
    #         it "should return nil" do
    #           next_page.next.should be_nil
    #         end
    #       end
    #     end
    #   end
    # end

    describe '#parents' do
      let(:parentparent) { create(:page) }
      let(:parent)       { create(:page, parent: parentparent) }
      let(:page)         { create(:page, parent: parent) }

      it "returns an array of all page parents" do
        expect(page.parents).to eq([parent, parentparent])
      end
    end

    describe '#publish!' do
      let(:page) { build_stubbed(:page, public: false) }
      let(:current_time) { Time.now }

      before do
        current_time
        allow(Time).to receive(:now).and_return(current_time)
        page.publish!
      end

      it "sets public attribute to true" do
        expect(page.public).to eq(true)
      end

      it "sets published_at attribute to current time" do
        expect(page.published_at).to eq(current_time)
      end
    end

    describe '#set_language_from_parent_or_default' do
      let(:default_language) { mock_model('Language', code: 'es') }
      let(:page) { Page.new }

      before { allow(page).to receive(:parent).and_return(parent) }

      subject { page }

      context "parent has a language" do
        let(:parent) { mock_model('Page', language: default_language, language_id: default_language.id, language_code: default_language.code) }

        before do
          page.send(:set_language_from_parent_or_default)
        end

        describe '#language_id' do
          subject { super().language_id }
          it { is_expected.to eq(parent.language_id) }
        end
      end

      context "parent has no language" do
        let(:parent) { mock_model('Page', language: nil, language_id: nil, language_code: nil) }

        before do
          allow(Language).to receive(:default).and_return(default_language)
          page.send(:set_language_from_parent_or_default)
        end

        describe '#language_id' do
          subject { super().language_id }
          it { is_expected.to eq(default_language.id) }
        end
      end
    end

    describe '#taggable?' do
      context "definition has 'taggable' key with true value" do
        it "should return true" do
          page = build(:page)
          allow(page).to receive(:definition).and_return({'name' => 'standard', 'taggable' => true})
          expect(page.taggable?).to be_truthy
        end
      end

      context "definition has 'taggable' key with foo value" do
        it "should return false" do
          page = build(:page)
          allow(page).to receive(:definition).and_return({'name' => 'standard', 'taggable' => 'foo'})
          expect(page.taggable?).to be_falsey
        end
      end

      context "definition has no 'taggable' key" do
        it "should return false" do
          page = build(:page)
          allow(page).to receive(:definition).and_return({'name' => 'standard'})
          expect(page.taggable?).to be_falsey
        end
      end
    end

    describe '#to_partial_path' do
      it "returns the path to pages page layout partial" do
        expect(page.to_partial_path).to eq('alchemy/page_layouts/foo')
      end
    end

    describe '#unlock!' do
      let(:page) { create(:page, locked: true, locked_by: 1) }

      before do
        allow(page).to receive(:save).and_return(true)
      end

      it "should set the locked status to false" do
        page.unlock!
        page.reload
        expect(page.locked).to eq(false)
      end

      it "should not update the timestamps " do
        expect { page.unlock! }.to_not change(page, :updated_at)
      end

      it "should set locked_by to nil" do
        page.unlock!
        page.reload
        expect(page.locked_by).to eq(nil)
      end

      it "sets current preview to nil" do
        Page.current_preview = page
        page.unlock!
        expect(Page.current_preview).to be_nil
      end
    end

    context 'urlname updating' do
      let(:parentparent)  { create(:page, name: 'parentparent') }
      let(:parent)        { create(:page, parent_id: parentparent.id, name: 'parent') }
      let(:page)          { create(:page, parent_id: parent.id, name: 'page') }
      let(:invisible)     { create(:page, parent_id: page.id, name: 'invisible', visible: false) }
      let(:contact)       { create(:page, parent_id: invisible.id, name: 'contact') }
      let(:language_root) { parentparent.parent }

      # TODO: find a solution for how we handle url updating and resolving in nodes
      # context "with activated url_nesting" do
      #   before { Config.stub(:get).and_return(true) }

      #   it "should store all parents urlnames delimited by slash" do
      #     page.urlname.should == 'parentparent/parent/page'
      #   end

      #   it "should not include the root page" do
      #     Page.root.update_column(:urlname, 'root')
      #     language_root.update(urlname: 'new-urlname')
      #     language_root.urlname.should_not =~ /root/
      #   end

      #   it "should not include the language root page" do
      #     page.urlname.should_not =~ /startseite/
      #   end

      #   it "should not include invisible pages" do
      #     contact.urlname.should_not =~ /invisible/
      #   end

      #   context "after changing page's urlname" do
      #     it "updates urlnames of descendants" do
      #       page
      #       parentparent.urlname = 'new-urlname'
      #       parentparent.save!
      #       page.reload
      #       page.urlname.should == 'new-urlname/parent/page'
      #     end

      #     it "should create a legacy url" do
      #       page.stub(:slug).and_return('foo')
      #       page.update_urlname!
      #       page.legacy_urls.should_not be_empty
      #       page.legacy_urls.pluck(:urlname).should include('parentparent/parent/page')
      #     end
      #   end

      #   context "after updating my visibility" do
      #     it "should update urlnames of descendants" do
      #       page
      #       parentparent.visible = false
      #       parentparent.save!
      #       page.reload
      #       page.urlname.should == 'parent/page'
      #     end
      #   end
      # end
    end

    # TODO: move to node sorting test
    # describe "#update_node!" do
    #
    #   let(:original_url) { "sample-url" }
    #   let(:page) { create(:page, :language => language, :urlname => original_url, restricted: false) }
    #   let(:node) { TreeNode.new(10, 11, 12, 13, "another-url", true) }
    #
    #   context "when nesting is enabled" do
    #
    #     context "when page is not external" do
    #
    #       before { page.stub(redirects_to_external?: false)}
    #
    #       it "should update all attributes" do
    #         page.update_node!(node)
    #         page.reload
    #         expect(page.lft).to eq(node.left)
    #         expect(page.rgt).to eq(node.right)
    #         expect(page.parent_id).to eq(node.parent)
    #         expect(page.depth).to eq(node.depth)
    #         expect(page.urlname).to eq(node.url)
    #         expect(page.restricted).to eq(node.restricted)
    #       end
    #
    #       context "when url is the same" do
    #         let(:node) { TreeNode.new(10, 11, 12, 13, original_url, true) }
    #
    #         it "should not create a legacy url" do
    #           page.update_node!(node)
    #           page.reload
    #           expect(page.legacy_urls.size).to eq(0)
    #         end
    #       end
    #
    #       context "when url is not the same" do
    #         it "should create a legacy url" do
    #           page.update_node!(node)
    #           page.reload
    #           expect(page.legacy_urls.size).to eq(1)
    #         end
    #       end
    #     end
    #
    #     context "when page is external" do
    #
    #       before { page.stub(redirects_to_external?: true) }
    #
    #       it "should update all attributes except url" do
    #         page.update_node!(node)
    #         page.reload
    #         expect(page.lft).to eq(node.left)
    #         expect(page.rgt).to eq(node.right)
    #         expect(page.parent_id).to eq(node.parent)
    #         expect(page.depth).to eq(node.depth)
    #         expect(page.urlname).to eq(original_url)
    #         expect(page.restricted).to eq(node.restricted)
    #       end
    #
    #       it "should not create a legacy url" do
    #         page.update_node!(node)
    #         page.reload
    #         expect(page.legacy_urls.size).to eq(0)
    #       end
    #     end
    #   end
    #
    #   context "when nesting is disabled" do
    #
    #     context "when page is not external" do
    #
    #       before { page.stub(redirects_to_external?: false)}
    #
    #       it "should update all attributes except url" do
    #         page.update_node!(node)
    #         page.reload
    #         expect(page.lft).to eq(node.left)
    #         expect(page.rgt).to eq(node.right)
    #         expect(page.parent_id).to eq(node.parent)
    #         expect(page.depth).to eq(node.depth)
    #         expect(page.urlname).to eq(original_url)
    #         expect(page.restricted).to eq(node.restricted)
    #       end
    #
    #       it "should not create a legacy url" do
    #         page.update_node!(node)
    #         page.reload
    #         expect(page.legacy_urls.size).to eq(0)
    #       end
    #
    #     end
    #
    #     context "when page is external" do
    #
    #       before { page.stub(redirects_to_external?: true) }
    #
    #       before { Alchemy::Config.stub(get: true) }
    #
    #       it "should update all attributes except url" do
    #         page.update_node!(node)
    #         page.reload
    #         expect(page.lft).to eq(node.left)
    #         expect(page.rgt).to eq(node.right)
    #         expect(page.parent_id).to eq(node.parent)
    #         expect(page.depth).to eq(node.depth)
    #         expect(page.urlname).to eq(original_url)
    #         expect(page.restricted).to eq(node.restricted)
    #       end
    #
    #       it "should not create a legacy url" do
    #         page.update_node!(node)
    #         page.reload
    #         expect(page.legacy_urls.size).to eq(0)
    #       end
    #     end
    #   end
    # end

    describe '#slug' do
      context "with parents path saved in urlname" do
        let(:page) { build(:page, urlname: 'root/parent/my-name')}

        it "should return the last part of the urlname" do
          expect(page.slug).to eq('my-name')
        end
      end

      context "with single urlname" do
        let(:page) { build(:page, urlname: 'my-name')}

        it "should return the last part of the urlname" do
          expect(page.slug).to eq('my-name')
        end
      end

      context "with nil as urlname" do
        let(:page) { build(:page, urlname: nil)}

        it "should return nil" do
          expect(page.slug).to be_nil
        end
      end
    end

    context 'page status methods' do
      let(:page) { build(:page, public: true, restricted: false, locked: false)}

      describe '#status' do
        it "returns a combined status hash" do
          expect(page.status).to eq({public: true, restricted: false, locked: false})
        end
      end

      describe '#status_title' do
        it "returns a translated status string for public status" do
          expect(page.status_title(:public)).to eq('Page is published.')
        end

        it "returns a translated status string for locked status" do
          expect(page.status_title(:locked)).to eq('')
        end

        it "returns a translated status string for restricted status" do
          expect(page.status_title(:restricted)).to eq('Page is not restricted.')
        end
      end
    end

    context 'indicate page editors' do
      let(:page) { Page.new }
      let(:user) { create(:editor_user) }

      describe '#creator' do
        before { page.update(creator_id: user.id) }

        it "returns the user that created the page" do
          expect(page.creator.id).to eq(user.id)
        end

        context 'with user class having a different primary key' do
          before do
            allow(Alchemy.user_class)
              .to receive(:primary_key)
              .and_return('user_id')

            allow(page)
              .to receive(:creator_id)
              .and_return(1)
          end

          it "returns the user that created the page" do
            expect(Alchemy.user_class)
              .to receive(:find_by)
              .with({'user_id' => 1})

            page.creator
          end
        end
      end

      describe '#updater' do
        before { page.update(updater_id: user.id) }

        it "returns the user that created the page" do
          expect(page.updater.id).to eq(user.id)
        end

        context 'with user class having a different primary key' do
          before do
            allow(Alchemy.user_class)
              .to receive(:primary_key)
              .and_return('user_id')

            allow(page)
              .to receive(:updater_id)
              .and_return(1)
          end

          it "returns the user that updated the page" do
            expect(Alchemy.user_class)
              .to receive(:find_by)
              .with({'user_id' => 1})

            page.updater
          end
        end
      end

      describe '#locker' do
        before { page.update(locked_by: user.id) }

        it "returns the user that created the page" do
          expect(page.locker.id).to eq(user.id)
        end

        context 'with user class having a different primary key' do
          before do
            allow(Alchemy.user_class)
              .to receive(:primary_key)
              .and_return('user_id')

            allow(page)
              .to receive(:locked_by)
              .and_return(1)
          end

          it "returns the user that locked the page" do
            expect(Alchemy.user_class)
              .to receive(:find_by)
              .with({'user_id' => 1})

            page.locker
          end
        end
      end

      context 'with user that can not be found' do
        it 'does not raise not found error' do
          %w(creator updater locker).each do |user_type|
            expect { page.send(user_type) }.to_not raise_error
          end
        end
      end

      context 'with user class having a name accessor' do
        let(:user) { double(name: 'Paul Page') }

        describe '#creator_name' do
          before { allow(page).to receive(:creator).and_return(user) }

          it "returns the name of the creator" do
            expect(page.creator_name).to eq('Paul Page')
          end
        end

        describe '#updater_name' do
          before { allow(page).to receive(:updater).and_return(user) }

          it "returns the name of the updater" do
            expect(page.updater_name).to eq('Paul Page')
          end
        end

        describe '#locker_name' do
          before { allow(page).to receive(:locker).and_return(user) }

          it "returns the name of the current page editor" do
            expect(page.locker_name).to eq('Paul Page')
          end
        end
      end

      context 'with user class not having a name accessor' do
        let(:user) { Alchemy.user_class.new }

        describe '#creator_name' do
          before { allow(page).to receive(:creator).and_return(user) }

          it "returns unknown" do
            expect(page.creator_name).to eq('unknown')
          end
        end

        describe '#updater_name' do
          before { allow(page).to receive(:updater).and_return(user) }

          it "returns unknown" do
            expect(page.updater_name).to eq('unknown')
          end
        end

        describe '#locker_name' do
          before { allow(page).to receive(:locker).and_return(user) }

          it "returns unknown" do
            expect(page.locker_name).to eq('unknown')
          end
        end
      end
    end

    it_behaves_like "having a hint" do
      let(:subject) { Page.new }
    end

    describe '#layout_partial_name' do
      let(:page) { Page.new(page_layout: 'Standard Page') }

      it "returns a partial renderer compatible name" do
        expect(page.layout_partial_name).to eq('standard_page')
      end
    end

    describe '#published_at' do
      context 'with published_at date set' do
        let(:published_at) { Time.now }
        let(:page)         { build_stubbed(:page, published_at: published_at) }

        it "returns the published_at value from database" do
          expect(page.published_at).to eq(published_at)
        end
      end

      context 'with published_at is nil' do
        let(:updated_at) { Time.now }
        let(:page)       { build_stubbed(:page, published_at: nil, updated_at: updated_at) }

        it "returns the updated_at value" do
          expect(page.published_at).to eq(updated_at)
        end
      end
    end
  end
end
