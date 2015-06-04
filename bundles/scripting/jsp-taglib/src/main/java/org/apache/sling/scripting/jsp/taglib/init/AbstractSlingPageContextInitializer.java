/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.apache.sling.scripting.jsp.taglib.init;

import javax.servlet.jsp.PageContext;

import org.apache.sling.api.scripting.SlingBindings;
import org.apache.sling.api.scripting.SlingScriptHelper;

/**
 * Abstract implementation of the PageContextInitializer.
 */
public abstract class AbstractSlingPageContextInitializer implements
		PageContextInitializer {

	protected PageContext pageContext;

	/**
	 * Get the Sling Bindings.
	 * 
	 * @return the sling bindings
	 */
	public SlingBindings getSlingBindings() {
		return (SlingBindings) pageContext.getRequest().getAttribute(
				SlingBindings.class.getName());
	}

	/**
	 * Get the Sling Script Helper.
	 * 
	 * @return the sling script helper
	 */
	public SlingScriptHelper getSlingScriptHelper() {
		return getSlingBindings().getSling();
	}

	/*
	 * (non-Javadoc)
	 * 
	 * @see
	 * org.apache.sling.scripting.jsp.taglib.init.PageContextInitializer#intitialize
	 * (javax.servlet.jsp.PageContext)
	 */
	public void intitialize(PageContext pageContext) {
		this.pageContext = pageContext;
	}

}
