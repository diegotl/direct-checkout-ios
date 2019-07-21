//
//  APIClient.swift
//  Core
//
//  Created by Diego Trevisan Lara on 07/11/18.
//  Copyright © 2018 Juno. All rights reserved.
//

public struct APIClient: IAPIClient {
    
    let strategy: IAPIStrategy
    
    public func execute<T: Decodable>(endpoint: APIEndpoint, completion: @escaping (Result<T, Error>) -> Void) {
        
        let request = endpoint.build()
        
        session.dataTask(with: request) { data, response, error in
            self.strategy.execute(data: data, response: response, error: error, completion: completion)
        }.resume()
        
    }
}
