# -*- encoding : utf-8 -*-
BillIt::Application.routes.draw do

  resources :votes


  resources :counts


  resources :vote_events


  resources :motions


  devise_for :admin_users, ActiveAdmin::Devise.config
  ActiveAdmin.routes(self)

  root :to => "bills#index"

  resources :paperworks do
    get 'search', on: :collection
  end

  resources :bills do
  	get 'feed', on: :member
  	get 'search', on: :collection
  	get 'last_update', on: :collection
  end
end
