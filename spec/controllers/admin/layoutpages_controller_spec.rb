require 'spec_helper'

module Alchemy
  describe Admin::LayoutpagesController do
    before { sign_in(admin_user) }

    describe "#index" do
      it "should assign @locked_pages" do
        alchemy_get :index
        expect(assigns(:locked_pages)).to eq([])
      end

      it "should assign @locked_pages" do
        alchemy_get :index
        expect(assigns(:layoutpages)).to eq(Page.layoutpages)
      end

      it "should assign @languages" do
        alchemy_get :index
        expect(assigns(:languages).first).to be_a(Language)
      end
    end
  end
end
